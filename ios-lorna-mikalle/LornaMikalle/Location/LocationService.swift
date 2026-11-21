import CoreLocation
import CoreMotion
import Observation
import simd

/// Real GPS input. Owns the session projection, a verified motion state (stationary / moving),
/// and a small Kalman filter that only runs while movement is confirmed.
///
/// Standing still: the position is anchored and GPS scatter is ignored, never integrated.
/// Starting to move needs agreeing evidence (Doppler speed or displacement beyond the adaptive
/// accuracy radius on consecutive fixes, vetoed when the phone's own motion sensors say it is
/// perfectly still). Unreliable fixes hold the last good position instead of moving Lorna.
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    enum Access { case notDetermined, denied, restricted, granted }
    enum MotionState { case stationary, moving }

    private(set) var access: Access = .notDetermined
    private(set) var projection: GeoProjection?

    /// Filtered position in planar metres relative to `projection.origin`.
    private(set) var position: SIMD2<Double> = .zero
    /// Filtered velocity in planar m/s (east, north).
    private(set) var velocity: SIMD2<Double> = .zero
    private(set) var speed: Double = 0
    private(set) var accuracy: Double = 0
    private(set) var lastFixDate: Date?
    private(set) var courseDegrees: Double?
    private(set) var deviceHeading: Double?
    private(set) var streetName: String?
    private(set) var hasFix = false
    /// Bumped when the projection origin is replaced (warm start turned out to be far away),
    /// so anything built in the old planar frame is thrown away.
    private(set) var projectionEpoch = 0
    /// The projection was primed from the last known area; the map can stream from disk while
    /// the first real fix arrives. Lorna is never moved by it.
    private(set) var isWarmStart = false
    /// Verified movement state (drives Lorna's idle / walk / run).
    private(set) var motionState: MotionState = .stationary
    var isMoving: Bool { motionState == .moving }
    /// False while recent fixes are too inaccurate to trust; the last good position is held.
    private(set) var signalReliable = true
    /// Distance walked this session, only counted while genuinely moving.
    private(set) var sessionDistance: Double = 0
    var onDistanceWalked: ((Double) -> Void)?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var variance: Double = 25
    private var lastTimestamp: Date?
    private var lastRawPlanar: SIMD2<Double>?
    private var lastGeocodePlanar: SIMD2<Double>?
    private var lastGeocodeDate: Date = .distantPast
    private var lastAreaSave: (planar: SIMD2<Double>, date: Date)?
    private static let lastAreaKey = "map.lastArea"

    // Motion verification.
    /// Where Lorna stands while stationary; GPS scatter around it is ignored.
    private var anchor: SIMD2<Double> = .zero
    private var anchorAccuracy: Double = 50
    /// Running mean of stationary fixes (accuracy-weighted), used only for slow, verified re-anchoring.
    private var stationaryMean: SIMD2<Double> = .zero
    private var stationaryWeight: Double = 0
    private var moveEvidence = 0
    private var stillEvidence = 0
    private var lastMoveDirection: SIMD2<Double>?
    /// Best recent accuracy, relaxing slowly so urban canyons adapt instead of freezing.
    private var bestAccuracy: Double = 30
    private var unreliableStreak = 0
    /// Consecutive large-innovation fixes while moving (a genuine relocation repeats; a glitch doesn't).
    private var outlierStreak = 0
    private var lastOutlier: SIMD2<Double>?

    // Device motion (no permission needed): RMS of user acceleration in g.
    @ObservationIgnored private let motion = CMMotionManager()
    @ObservationIgnored private var motionLevel: Double = 0
    private var motionAvailable: Bool { motion.isDeviceMotionAvailable }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.distanceFilter = kCLDistanceFilterNone
        manager.headingFilter = 4
        updateAccess(manager.authorizationStatus)
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        guard access == .granted else { return }
        primeFromLastKnownArea()
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
        startMotion()
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        motion.stopDeviceMotionUpdates()
    }

    private func startMotion() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 15
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let a = data?.userAcceleration else { return }
            let m2 = a.x * a.x + a.y * a.y + a.z * a.z
            MainActor.assumeIsolated {
                guard let self else { return }
                // ~1.5 s exponential window.
                let ms = self.motionLevel * self.motionLevel * 0.955 + m2 * 0.045
                self.motionLevel = sqrt(ms)
            }
        }
    }

    /// Phone sensors say "held still" (standing, phone in hand or on a table). Nil when unavailable.
    private var deviceStill: Bool? { motionAvailable ? motionLevel < 0.035 : nil }
    /// Phone sensors show a walking/running rhythm.
    private var deviceActive: Bool { motionAvailable && motionLevel > 0.07 }

    /// Heading to show in the HUD: travel course while moving, compass otherwise.
    var displayHeading: Double? {
        if speed > 0.6, let courseDegrees { return courseDegrees }
        return deviceHeading ?? courseDegrees
    }

    /// Position extrapolated from the last fix (bridges the ~1 s GPS cadence).
    func predictedPosition(at date: Date = .now) -> SIMD2<Double> {
        guard let lastFixDate else { return position }
        let dt = min(max(date.timeIntervalSince(lastFixDate), 0), 1.5)
        return position + velocity * dt
    }

    // MARK: - Warm start

    /// Primes the map projection from where the phone last was, so saved streets can appear
    /// before the first precise fix. Uses the system's cached location when recent, else the
    /// approximate area (~110 m, stored only on this device) saved during the last session.
    private func primeFromLastKnownArea() {
        guard projection == nil else { return }
        var coordinate: CLLocationCoordinate2D?
        if let cached = manager.location, cached.horizontalAccuracy > 0, cached.horizontalAccuracy <= 500,
           abs(cached.timestamp.timeIntervalSinceNow) < 24 * 3600 {
            coordinate = cached.coordinate
        } else if let saved = UserDefaults.standard.array(forKey: Self.lastAreaKey) as? [Double], saved.count == 3,
                  Date().timeIntervalSince1970 - saved[2] < 30 * 24 * 3600 {
            coordinate = CLLocationCoordinate2D(latitude: saved[0], longitude: saved[1])
        }
        guard let coordinate, CLLocationCoordinate2DIsValid(coordinate) else { return }
        projection = GeoProjection(origin: coordinate)
        isWarmStart = true
    }

    private func saveAreaIfNeeded(_ coordinate: CLLocationCoordinate2D) {
        if let last = lastAreaSave, simd_distance(last.planar, position) < 150, Date().timeIntervalSince(last.date) < 300 { return }
        lastAreaSave = (position, .now)
        let rounded = [(coordinate.latitude * 1000).rounded() / 1000, (coordinate.longitude * 1000).rounded() / 1000, Date().timeIntervalSince1970]
        UserDefaults.standard.set(rounded, forKey: Self.lastAreaKey)
    }

    // MARK: - Delegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.updateAccess(status)
            if self.access == .granted { self.start() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for location in locations { self.ingest(location) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in self.deviceHeading = value }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    // MARK: - Filtering

    private func updateAccess(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse: access = .granted
        case .denied: access = .denied
        case .restricted: access = .restricted
        default: access = .notDetermined
        }
    }

    private func ingest(_ location: CLLocation) {
        let acc = location.horizontalAccuracy
        guard acc > 0, acc <= 100 else { return }
        guard abs(location.timestamp.timeIntervalSinceNow) < 15 else { return }

        guard hasFix, let projection else {
            // First fix: wait for something usable so Lorna doesn't start in the wrong street.
            guard acc <= 65 else { return }
            var start = SIMD2<Double>.zero
            if let warm = self.projection, isWarmStart, simd_length(warm.planar(location.coordinate)) < 2500 {
                // Keep the warm frame (tiles already built in it); place Lorna at the real fix.
                start = warm.planar(location.coordinate)
            } else {
                if self.projection != nil { projectionEpoch += 1 }
                self.projection = GeoProjection(origin: location.coordinate)
            }
            isWarmStart = false
            position = start
            anchor = start
            anchorAccuracy = acc
            stationaryMean = start
            stationaryWeight = 1 / (acc * acc)
            variance = acc * acc
            accuracy = acc
            bestAccuracy = acc
            lastTimestamp = location.timestamp
            lastFixDate = .now
            lastRawPlanar = start
            hasFix = true
            saveAreaIfNeeded(location.coordinate)
            geocodeIfNeeded(location)
            return
        }

        let measured = projection.planar(location.coordinate)
        let dt = max(0.05, location.timestamp.timeIntervalSince(lastTimestamp ?? location.timestamp))
        lastTimestamp = location.timestamp
        let rawStep = measured - (lastRawPlanar ?? measured)
        lastRawPlanar = measured
        accuracy = acc

        // 1. Reliability: adaptive to the recent best accuracy (relaxes ~1 m per 2 s), so a city
        //    canyon with steady 30 m fixes still moves Lorna, but a sudden degradation is held.
        bestAccuracy = min(acc, bestAccuracy + 0.5 * dt)
        let reliableLimit = min(65, max(20, bestAccuracy * 2.2 + 6))
        guard acc <= reliableLimit else {
            unreliableStreak += 1
            if unreliableStreak >= 2 { signalReliable = false }
            holdOnUnreliable(dt: dt)
            return
        }
        unreliableStreak = 0
        signalReliable = true

        // 2. Doppler speed from the GPS chip, trusted only when its own error bar allows.
        var doppler: Double?
        var course: Double?
        if location.speed >= 0 {
            let sAcc = location.speedAccuracy
            if sAcc < 0 || sAcc < max(0.6, location.speed * 0.8) { doppler = location.speed }
            if location.course >= 0, location.speed > 0.5 { course = location.course }
        }
        // Displacement threshold scales with accuracy: noise inside the error circle is not motion.
        let threshold = min(max(acc * 0.9, 4), 20)

        switch motionState {
        case .stationary:
            ingestStationary(measured: measured, acc: acc, doppler: doppler, course: course, threshold: threshold)
        case .moving:
            ingestMoving(measured: measured, acc: acc, dt: dt, doppler: doppler, course: course, rawStep: rawStep)
        }
        lastFixDate = .now
        geocodeIfNeeded(location)
        saveAreaIfNeeded(location.coordinate)
    }

    /// Stationary: Lorna stays on the anchor. Scatter is never integrated into position.
    private func ingestStationary(measured: SIMD2<Double>, acc: Double, doppler: Double?, course: Double?, threshold: Double) {
        speed = 0
        velocity = .zero
        let offset = measured - anchor
        let distance = simd_length(offset)

        let dopplerSaysMoving = (doppler ?? 0) >= 0.7
        let displaced = distance > threshold
        // Displacement must keep pointing the same way across fixes; scatter flips around.
        var consistent = true
        if displaced, let previous = lastMoveDirection {
            consistent = simd_dot(previous, offset / distance) > 0.5
        }
        let gpsEvidence = dopplerSaysMoving || (displaced && consistent)
        // A phone held perfectly still vetoes GPS evidence (unless clearly in a vehicle).
        let vetoed = deviceStill == true && (doppler ?? 0) < 2.5

        if gpsEvidence && !vetoed {
            moveEvidence += 1
            lastMoveDirection = distance > 0.5 ? offset / distance : lastMoveDirection
        } else {
            moveEvidence = 0
            lastMoveDirection = nil
        }
        // Responsive start: two agreeing fixes, or one when the phone shows a walking rhythm
        // and the Doppler speed agrees.
        let needed = deviceActive && dopplerSaysMoving ? 1 : 2
        if moveEvidence >= needed {
            beginMoving(from: measured, acc: acc, doppler: doppler, course: course)
            return
        }

        // Verified re-anchoring: average stationary fixes; only move the anchor when a much
        // better fix shows it is clearly off (initial coarse fix). The scene slides there idle.
        if !displaced || acc < anchorAccuracy * 0.6 {
            let w = 1 / (acc * acc)
            stationaryMean = (stationaryMean * stationaryWeight + measured * w) / (stationaryWeight + w)
            stationaryWeight = min(stationaryWeight + w, 4 / (bestAccuracy * bestAccuracy))
        }
        if acc < anchorAccuracy * 0.6, simd_distance(stationaryMean, anchor) > max(acc, 3) {
            anchor = stationaryMean
            anchorAccuracy = acc
        } else {
            anchorAccuracy = min(anchorAccuracy, max(acc, anchorAccuracy * 0.98))
        }
        position = anchor
    }

    private func beginMoving(from measured: SIMD2<Double>, acc: Double, doppler: Double?, course: Double?) {
        motionState = .moving
        moveEvidence = 0
        stillEvidence = 0
        outlierStreak = 0
        position = anchor
        variance = max(acc * acc * 0.5, 4)
        let direction = lastMoveDirection ?? simd_normalize(measured - anchor + SIMD2(1e-6, 0))
        let s = min(max(doppler ?? 1.2, 0.8), 6)
        if let course {
            let rad = course * .pi / 180
            velocity = SIMD2(sin(rad), cos(rad)) * s
            courseDegrees = course
        } else {
            velocity = direction * s
        }
        speed = s
    }

    /// Moving: velocity-aided Kalman filter with an innovation gate against jumps.
    private func ingestMoving(measured: SIMD2<Double>, acc: Double, dt: Double, doppler: Double?, course: Double?, rawStep: SIMD2<Double>) {
        // Velocity: prefer the GPS chip's Doppler speed/course, else derive from the raw step.
        var gpsVelocity: SIMD2<Double>
        var measuredSpeed: Double
        if let doppler, let course {
            let rad = course * .pi / 180
            measuredSpeed = doppler
            gpsVelocity = SIMD2(sin(rad), cos(rad)) * doppler
            courseDegrees = course
        } else if let doppler {
            measuredSpeed = doppler
            let len = simd_length(rawStep)
            gpsVelocity = len > 0.3 ? rawStep / len * doppler : velocity
        } else {
            gpsVelocity = rawStep / dt
            measuredSpeed = simd_length(gpsVelocity)
        }

        // Stop detection (with hysteresis against the 0.7 m/s start threshold).
        let slow = measuredSpeed < 0.35 || (deviceStill == true && measuredSpeed < 1.0)
        stillEvidence = slow ? stillEvidence + 1 : 0
        if stillEvidence >= 2 {
            settle(at: position)
            return
        }
        if slow {
            gpsVelocity = .zero
            measuredSpeed = 0
        }

        // Predict.
        let previous = position
        let predicted = position + velocity * dt

        // Innovation gate: a fix far outside what walking/running could explain is a glitch,
        // unless it repeats from the same place (genuine relocation after signal recovery).
        let innovation = simd_distance(measured, predicted)
        let plausible = max(acc * 3, 12 + measuredSpeed * dt * 2)
        if innovation > plausible {
            if let lastOutlier, simd_distance(lastOutlier, measured) < max(acc * 1.5, 10) {
                outlierStreak += 1
            } else {
                outlierStreak = 1
            }
            lastOutlier = measured
            if outlierStreak < 3 {
                position = predicted
                velocity *= 0.8
                speed = simd_length(velocity)
                return
            }
            // Confirmed relocation: accept it (the scene snaps if it is far).
            position = measured
            variance = acc * acc
            outlierStreak = 0
            lastOutlier = nil
            return
        }
        outlierStreak = 0
        lastOutlier = nil

        position = predicted
        variance += (1.2 + measuredSpeed) * (1.2 + measuredSpeed) * dt
        let gain = variance / (variance + acc * acc)
        position += (measured - position) * gain
        variance *= (1 - gain)

        velocity = velocity * 0.35 + gpsVelocity * 0.65
        speed = speed * 0.35 + measuredSpeed * 0.65

        let step = simd_length(position - previous)
        if step < 25 {
            sessionDistance += step
            onDistanceWalked?(step)
        }
    }

    /// Becomes stationary on the current filtered position (no snap back to old fixes).
    private func settle(at point: SIMD2<Double>) {
        motionState = .stationary
        stillEvidence = 0
        moveEvidence = 0
        lastMoveDirection = nil
        anchor = point
        anchorAccuracy = max(accuracy, 5)
        stationaryMean = point
        stationaryWeight = 1 / (anchorAccuracy * anchorAccuracy)
        position = point
        velocity = .zero
        speed = 0
    }

    /// Unreliable fix: hold the last reliable position. While moving, coast briefly on the
    /// last velocity (decaying), then hold; never move toward the bad coordinate.
    private func holdOnUnreliable(dt: Double) {
        guard motionState == .moving else {
            position = anchor
            return
        }
        if unreliableStreak <= 3 {
            velocity *= 0.6
            speed = simd_length(velocity)
            position += velocity * min(dt, 1.5)
            lastFixDate = .now
        } else {
            settle(at: position)
        }
    }

    private func geocodeIfNeeded(_ location: CLLocation) {
        guard let projection else { return }
        let here = projection.planar(location.coordinate)
        let movedFar = lastGeocodePlanar.map { simd_length($0 - here) > 40 } ?? true
        guard movedFar, Date.now.timeIntervalSince(lastGeocodeDate) > 12, !geocoder.isGeocoding else { return }
        lastGeocodeDate = .now
        lastGeocodePlanar = here
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            let name = placemarks?.first?.thoroughfare ?? placemarks?.first?.name
            Task { @MainActor [self] in
                if let name { self?.streetName = name }
            }
        }
    }
}
