import CoreLocation
import Network
import RealityKit
import SwiftUI
import UIKit
import simd

/// Snapshot of the live world handed to encounter stages (clones share meshes, so it is cheap).
struct EncounterStageSource {
    let world: Entity
    let origin: SIMD3<Float>
    let forwardYaw: Float
    let preset: LightingPreset
    let weather: WeatherCondition
    let sunAzimuth: Double
    let sunElevation: Double?
}

/// Owns the explore RealityKit scene: streamed real-map tiles, Lorna, spirits, places, sky and the follow camera.
final class ExplorationScene {
    let root = Entity()
    private let worldRoot = Entity()
    private let poiRoot = Entity()
    private let ground = ModelEntity()
    private let sky = SkyRig()
    private let camera = PerspectiveCamera()
    private let lorna = LornaCharacter()
    private let story = StoryPresence()
    /// 0 = normal follow camera, 1 = story push-in on the landmark or Giulia.
    private var cinematic: Float = 0
    private var cinematicFocus: SIMD3<Float>?
    private var wasLaunching = false
    private let headingWedge = ModelEntity()
    private let footRing = ModelEntity()

    // MARK: Tile streaming state

    private enum TileState {
        case loading
        case loaded(WorldChunk, fromCache: Bool)
        case failed(attempts: Int, retryAt: Date, error: String)
    }
    private var tiles: [TileKey: TileState] = [:]
    /// Disk loads (saved tiles) and network loads are throttled separately: saved streets never
    /// queue behind a slow download, and Overpass gets at most two requests from us at once
    /// (its per-IP slot limit), so we stay clear of 429s and their back-off.
    private var diskInFlight = 0
    private var netInFlight = 0
    private static let maxDisk = 2
    private static let maxNetwork = 2
    /// Tiles shown from an old saved copy, refreshed quietly when the network is idle.
    private var staleTiles: Set<TileKey> = []
    /// Tiles whose prefetch failed this session (not retried until the next launch).
    private var prefetchSkipped: Set<TileKey> = []
    private var backgroundFetchBusy = false
    /// Matches `LocationService.projectionEpoch`; anything built in an older frame is dropped.
    private var worldEpoch = 0
    /// Lightweight first-look chunks (from one small fast query), replaced tile by tile.
    private var previews: [TileKey: WorldChunk] = [:]
    private var previewRequested = false
    private var fading: [(entity: Entity, t: Float)] = []

    /// Every chunk currently on screen: full tiles plus previews still standing in for missing ones.
    private var visibleChunks: [WorldChunk] {
        var out: [WorldChunk] = []
        for case .loaded(let chunk, _) in tiles.values { out.append(chunk) }
        out += previews.values
        return out
    }
    private var streamTimer: Float = 10
    private var mergeDirty = false
    private let pathMonitor = NWPathMonitor()
    private var networkAvailable = true

    // Merged data from loaded tiles
    private var roadSamples: [SIMD2<Double>] = []
    private var occluders: [SIMD2<Int32>: Float] = [:]
    private var greenCells: Set<SIMD2<Int32>> = []
    private var pois: [PlacedPOI] = []
    private var poiEntities: [Int: Entity] = [:]

    private var spirits: [SpiritEntity] = []
    private var spawnedInitial = false
    private var appliedPreset: LightingPreset?
    private var appliedWeather: WeatherCondition?

    private var displayed: SIMD2<Double> = .zero
    private var visualVelocity: SIMD2<Double> = .zero
    private var visualSpeed: Double = 0
    private var poseDwell: Float = 0
    private var playbackRate: Float = 1
    private var lornaYaw: Float = 0
    private var wedgeYaw: Float = 0
    private var hasPlacedPlayer = false
    private var clock: Float = 0
    private var infoTimer: Float = 0
    private var poiTimer: Float = 0
    private var ambienceTimer: Float = 5
    private var sunTimer: Float = 100
    private var spawnTimer: Float = 0
    private var lastWeatherFetch: Date?
    private var sunAzimuth: Double = 250
    private var sunElevation: Double?

    // Orbit camera (driven by gestures)
    var cameraYaw: Float = 0
    var cameraPitch: Float = 35 * .pi / 180
    var cameraDistance: Float = 9
    private var effectiveDistance: Float = 9
    private var occlusionLift: Float = 0
    private var cameraTarget: SIMD3<Float>?
    var viewSize: CGSize = .init(width: 390, height: 844)
    static let fieldOfView: Float = 55

    private var subscription: EventSubscription?
    private weak var game: GameState?
    private weak var location: LocationService?
    private var lastResetToken = 0

    init() {
        root.addChild(sky.root)
        root.addChild(worldRoot)
        root.addChild(poiRoot)

        var groundMesh = MeshBuilder()
        groundMesh.addQuad([-1400, 0, -1400], [1400, 0, -1400], [1400, 0, 1400], [-1400, 0, 1400], normal: [0, 1, 0])
        ground.model = ModelComponent(mesh: groundMesh.makeMesh(name: "ground") ?? .generatePlane(width: 2800, depth: 2800), materials: [])
        ground.position.y = -0.02
        ground.components.set(DynamicLightShadowComponent(castsShadow: false))
        root.addChild(ground)

        camera.camera.fieldOfViewInDegrees = Self.fieldOfView
        camera.camera.near = 0.1
        camera.camera.far = 1500
        root.addChild(camera)

        root.addChild(lorna.container)
        root.addChild(story.root)
        buildPlayerMarkers()
    }

    deinit { pathMonitor.cancel() }

    func setup(in content: inout RealityViewCameraContent, game: GameState, location: LocationService) async {
        self.game = game
        self.location = location
        content.add(root)
        applyAtmosphere(force: true, animated: false)
        updateCamera(dt: 1)

        game.onSpiritCalmed = { [weak self] id in self?.calm(spiritID: id) }
        game.stageProvider = { [weak self] in self?.makeStageSource() }

        pathMonitor.pathUpdateHandler = { [weak self] path in
            let ok = path.status == .satisfied
            Task { @MainActor [self] in self?.networkChanged(available: ok) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "lorna.network"))

        subscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.update(dt: Float(min(event.deltaTime, 0.1)))
        }
        Task.detached(priority: .background) { await OSMService.housekeeping() }
        worldEpoch = location.projectionEpoch
        await lorna.build()
        // Giulia loads after the first frame so she never delays the map or Lorna.
        Task { [story] in await story.load() }
    }

    // MARK: - Frame loop

    private func update(dt: Float) {
        guard let game, let location else { return }
        clock += dt
        if location.projectionEpoch != worldEpoch { resetWorld(epoch: location.projectionEpoch) }

        // 1. Player position: ease toward the filtered, velocity-predicted GPS position.
        //    This never waits on map loading.
        if location.hasFix {
            let target = location.predictedPosition()
            let gap = simd_distance(target, displayed)
            // Far gaps only happen after a confirmed GPS relocation: snap instead of sprinting.
            if !hasPlacedPlayer || gap > (location.isMoving ? 35 : 80) {
                displayed = target
                hasPlacedPlayer = true
                visualVelocity = .zero
                cameraTarget = nil
            } else {
                let k = Double(1 - exp(-dt * 4.5))
                let previous = displayed
                var step = (target - displayed) * k
                // Speed cap: verified pace while moving; a gentle idle slide for stationary
                // re-anchoring, so corrections never look like steps or jumps.
                let maxSpeed = location.isMoving ? max(3.5, location.speed * 1.6) : 0.6
                let stepLength = simd_length(step)
                let maxStep = maxSpeed * Double(dt)
                if stepLength > maxStep, stepLength > 0 { step *= maxStep / stepLength }
                displayed += step
                // On-screen velocity drives the animation, so feet match what the eye sees.
                if dt > 0 {
                    let instant = (displayed - previous) / Double(dt)
                    let s = Double(1 - exp(-dt * 3))
                    visualVelocity += (instant - visualVelocity) * s
                }
            }
        }
        visualSpeed = simd_length(visualVelocity)
        let worldPos = GeoProjection.world(displayed)
        lorna.container.position = worldPos
        ground.position = SIMD3(worldPos.x.rounded(), -0.02, worldPos.z.rounded())
        sky.follow(worldPos)
        sky.update(dt: dt)

        // 2. Facing + animation from real movement.
        updateLocomotion(dt: dt)
        if game.encounter == nil, game.storyRun == nil {
            AudioManager.shared.footstep(interval: lorna.stepInterval, running: lorna.pose == .run,
                                         onGrass: greenCells.contains(WorldGrid.cell(displayed)))
        }

        // Heading wedge (compass or course).
        if let heading = location.displayHeading {
            headingWedge.isEnabled = true
            let target = Float(.pi - heading * .pi / 180)
            wedgeYaw += Self.wrap(target - wedgeYaw) * min(1, dt * 8)
            headingWedge.orientation = simd_quatf(angle: wedgeYaw, axis: [0, 1, 0])
        } else {
            headingWedge.isEnabled = false
        }
        headingWedge.position = worldPos
        footRing.position = worldPos

        // 3. Camera with building collision.
        if game.cameraResetToken != lastResetToken {
            lastResetToken = game.cameraResetToken
            cameraPitch = 35 * .pi / 180
            cameraDistance = 9
            cameraYaw = lornaYaw + .pi
        }
        if game.followHeading {
            cameraYaw += Self.wrap((lornaYaw + .pi) - cameraYaw) * min(1, dt * 2)
        }
        updateCamera(dt: dt)

        // 4. Story in the world, spirits + places.
        story.update(dt: dt, game: game, lorna: displayed, lornaMoving: location.isMoving, hasFix: location.hasFix,
                     cameraYaw: cameraYaw, roadSamples: roadSamples) { [occluders] p in
            (occluders[WorldGrid.cell(p)] ?? 0) > 0.5
        }
        for spirit in spirits { spirit.update(deltaTime: dt) }
        animatePOIs(dt: dt)
        updateScreenOverlays(game: game)

        infoTimer += dt
        if infoTimer > 0.25 {
            infoTimer = 0
            game.spirits = spirits.map {
                SpiritInfo(id: $0.id, kind: $0.kind, distance: simd_distance($0.position, displayed))
            }
        }
        poiTimer += dt
        if poiTimer > 0.5, location.hasFix {
            poiTimer = 0
            updatePOIInfo(game: game)
        }

        // 5. Real sun, live weather and their transitions.
        sunTimer += dt
        if sunTimer > 30, let projection = location.projection {
            sunTimer = 0
            let coordinate = projection.coordinate(planar: displayed)
            let sun = SolarClock.sun(at: .now, coordinate: coordinate)
            sunAzimuth = sun.azimuth
            sunElevation = sun.elevation
            game.autoPreset = LightingPreset.from(sunElevation: sun.elevation)
            applyAtmosphere(force: true, animated: true)
            fetchWeatherIfNeeded(at: coordinate)
        }
        if game.activePreset != appliedPreset || game.activeWeather != appliedWeather {
            applyAtmosphere(force: false, animated: true)
        }
        ambienceTimer += dt
        if ambienceTimer > 2 {
            ambienceTimer = 0
            updateAmbience(game: game)
        }

        // 6. Map streaming + spirit population. Streaming starts as soon as there is a frame of
        //    reference (a warm start from the last known area), not only after the first fix.
        streamTimer += dt
        if location.projection != nil, streamTimer > 0.5 {
            streamTimer = 0
            streamTiles(game: game, location: location)
        }
        if mergeDirty { mergeTiles() }
        updateFades(dt: dt)
        spawnTimer += dt
        if location.hasFix, spawnTimer > 1 {
            spawnTimer = 0
            maintainSpirits(game: game)
        }
    }

    /// Pose with hysteresis + minimum dwell (no flicker at threshold speeds), cadence matched to
    /// on-screen speed, and facing that follows the actual direction of travel.
    private func updateLocomotion(dt: Float) {
        // Only verified movement animates Lorna; idle slides (re-anchoring) keep her standing.
        let verified = location?.isMoving ?? false
        let s = verified ? visualSpeed : 0
        poseDwell += dt
        let current = lorna.pose ?? .idle
        var next = current
        switch current {
        case .idle: if s > 2.6 { next = .run } else if s > 0.45 { next = .walk }
        case .walk: if s > 2.6 { next = .run } else if s < 0.25 { next = .idle }
        case .run: if s < 0.25 { next = .idle } else if s < 2.1 { next = .walk }
        }
        if next != current, poseDwell > 0.5 || lorna.pose == nil {
            lorna.setPose(next)
            poseDwell = 0
        }

        let targetRate: Float
        switch lorna.pose ?? .idle {
        case .idle: targetRate = 1
        case .walk: targetRate = Float(min(max(s / 1.35, 0.6), 1.6))
        case .run: targetRate = Float(min(max(s / 3.6, 0.75), 1.45))
        }
        playbackRate += (targetRate - playbackRate) * min(1, dt * 4)
        lorna.setPlaybackSpeed(playbackRate)

        if s > 0.3 {
            let desired = atan2(Float(visualVelocity.x), Float(-visualVelocity.y))
            let delta = Self.wrap(desired - lornaYaw)
            let maxStep = 4.5 * dt // rad/s turn-rate limit
            lornaYaw += max(-maxStep, min(maxStep, delta * min(1, dt * 7)))
        }
        lorna.face(yaw: lornaYaw)
    }

    private static func wrap(_ a: Float) -> Float {
        var d = a
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        return d
    }

    // MARK: - Camera

    private func updateCamera(dt: Float) {
        // Story push-in: when a chapter starts, the camera glides toward the story landmark or
        // Giulia, then eases back out after the story closes.
        if let game {
            let launching = game.storyLaunching
            if launching, !wasLaunching {
                cinematicFocus = storyFocus()
                story.celebrate()
            }
            wasLaunching = launching
            let goalBlend: Float = launching || game.storyRun != nil ? 1 : 0
            cinematic += (goalBlend - cinematic) * min(1, dt * (goalBlend > cinematic ? 4 : 1.6))
            if cinematic < 0.001, goalBlend == 0 { cinematic = 0; cinematicFocus = nil }
        }
        let c = cinematic * cinematic * (3 - 2 * cinematic)

        // Damped follow target: GPS corrections never jerk the view.
        var goal = lorna.container.position + SIMD3(0, 1.1, 0)
        if let focus = cinematicFocus, c > 0 {
            goal += ((lorna.container.position + focus) / 2 + SIMD3(0, 1.2, 0) - goal) * c
        }
        var target = cameraTarget ?? goal
        target += (goal - target) * min(1, dt * 9)
        cameraTarget = target

        // In a narrow street, first tilt up over the rooftops, then pull in only if still blocked.
        func firstHit(pitch: Float) -> Float? {
            let dir = SIMD3<Float>(sin(cameraYaw) * cos(pitch), sin(pitch), cos(cameraYaw) * cos(pitch))
            var d: Float = 1.5
            while d < baseDistance {
                let p = target + dir * d
                if let h = occluders[WorldGrid.cell(SIMD2(p.x, -p.z))], h > p.y { return d }
                d += 0.6
            }
            return nil
        }
        let basePitch = cameraPitch + (16 * .pi / 180 - cameraPitch) * c
        let baseDistance = cameraDistance + (5.5 - cameraDistance) * c
        let maxLift = max(0, 72 * .pi / 180 - basePitch)
        var wantedLift: Float = 0
        if firstHit(pitch: basePitch + occlusionLift) != nil || firstHit(pitch: basePitch) != nil {
            wantedLift = maxLift
            for step in 1...6 {
                let lift = maxLift * Float(step) / 6
                if firstHit(pitch: basePitch + lift) == nil { wantedLift = lift; break }
            }
        }
        occlusionLift += (wantedLift - occlusionLift) * min(1, dt * (wantedLift > occlusionLift ? 5 : 1.5))
        let pitch = basePitch + occlusionLift
        let dir = SIMD3<Float>(sin(cameraYaw) * cos(pitch), sin(pitch), cos(cameraYaw) * cos(pitch))

        var allowed = baseDistance
        if let hit = firstHit(pitch: pitch) { allowed = max(3.2, hit - 0.8) }
        let k = allowed < effectiveDistance ? min(1, dt * 6) : min(1, dt * 1.8)
        effectiveDistance += (allowed - effectiveDistance) * k
        camera.look(at: target, from: target + dir * effectiveDistance, relativeTo: nil)
    }

    /// What the story camera frames: Giulia when she is close, else the story landmark nearby.
    private func storyFocus() -> SIMD3<Float>? {
        if let g = story.giuliaPlanar, simd_distance(g, displayed) < 40 { return GeoProjection.world(g, y: 0.4) }
        if let l = story.landmarkPlanar, simd_distance(l, displayed) < 60 { return GeoProjection.world(l, y: 1.2) }
        return nil
    }

    /// True when a building blocks the line from the camera to Lorna's chest.
    private func isLornaHidden() -> Bool {
        let cam = camera.position(relativeTo: nil)
        let chest = lorna.container.position + SIMD3(0, 1.0, 0)
        let delta = chest - cam
        let length = simd_length(delta)
        guard length > 1 else { return false }
        var t: Float = 0.5
        while t < length - 0.6 {
            let p = cam + delta * (t / length)
            if let h = occluders[WorldGrid.cell(SIMD2(p.x, -p.z))], h > p.y { return true }
            t += 0.75
        }
        return false
    }

    private func project(_ point: SIMD3<Float>, inverse: simd_float4x4) -> CGPoint? {
        let tanHalf = tan(Self.fieldOfView * .pi / 360)
        let aspect = Float(viewSize.width / max(viewSize.height, 1))
        let p = inverse * SIMD4(point, 1)
        guard p.z < -0.5 else { return nil }
        let ndcX = (p.x / -p.z) / (tanHalf * aspect)
        let ndcY = (p.y / -p.z) / tanHalf
        guard abs(ndcX) < 1.2, abs(ndcY) < 1.2 else { return nil }
        return CGPoint(x: CGFloat((ndcX + 1) / 2) * viewSize.width, y: CGFloat((1 - ndcY) / 2) * viewSize.height)
    }

    private func updateScreenOverlays(game: GameState) {
        let inverse = camera.transformMatrix(relativeTo: nil).inverse
        var positions: [UUID: CGPoint] = [:]
        for spirit in spirits where simd_distance(spirit.position, displayed) < 220 {
            if let point = project(spirit.labelAnchor, inverse: inverse) { positions[spirit.id] = point }
        }
        let changed = positions.count != game.labelPositions.count || positions.contains { id, point in
            guard let old = game.labelPositions[id] else { return true }
            return abs(old.x - point.x) > 0.75 || abs(old.y - point.y) > 0.75
        }
        if changed { game.labelPositions = positions }

        var poiPositions: [Int: CGPoint] = [:]
        for poi in pois where simd_distance(poi.position, displayed) < 160 {
            if let point = project(GeoProjection.world(poi.position, y: 3.6), inverse: inverse) { poiPositions[poi.id] = point }
        }
        // Story labels: the landmark (visible from far away) and Giulia.
        var markers: [StoryMarker] = []
        if let anchor = story.landmarkLabelAnchor, let point = project(anchor, inverse: inverse) {
            markers.append(StoryMarker(kind: .landmark, point: point))
        }
        if let anchor = story.giuliaLabelAnchor, let point = project(anchor, inverse: inverse) {
            markers.append(StoryMarker(kind: .giulia, point: point))
        }
        if markers.map(\.kind) != game.storyMarkers.map(\.kind)
            || zip(markers, game.storyMarkers).contains(where: { abs($0.point.x - $1.point.x) > 0.75 || abs($0.point.y - $1.point.y) > 0.75 }) {
            game.storyMarkers = markers
        }

        if poiPositions.keys.sorted() != game.poiLabelPositions.keys.sorted()
            || poiPositions.contains(where: { id, p in
                guard let o = game.poiLabelPositions[id] else { return true }
                return abs(o.x - p.x) > 0.75 || abs(o.y - p.y) > 0.75 }) {
            game.poiLabelPositions = poiPositions
        }

        // Golden marker where Lorna is when buildings still hide her.
        let marker = hasPlacedPlayer && isLornaHidden()
            ? project(lorna.container.position + SIMD3(0, 1.0, 0), inverse: inverse) : nil
        if marker != game.occludedMarker {
            if let m = marker, let old = game.occludedMarker, abs(m.x - old.x) < 0.75, abs(m.y - old.y) < 0.75 { return }
            game.occludedMarker = marker
        }
    }

    // MARK: - Atmosphere

    private func applyAtmosphere(force: Bool, animated: Bool) {
        guard let game else { return }
        let preset = game.activePreset
        let weather = game.activeWeather
        guard force || preset != appliedPreset || weather != appliedWeather else { return }
        appliedPreset = preset
        appliedWeather = weather
        let wet = weather == .rain
        sky.apply(preset, weather: weather, sunAzimuth: sunAzimuth, sunElevation: sunElevation, animated: animated)
        ground.model?.materials = [WorldMaterials.shared.material(.ground, preset: preset, wet: wet)]
        for chunk in visibleChunks { chunk.apply(preset, wet: wet) }
        let crystal = WorldMaterials.shared.material(.poiCrystal, preset: preset)
        for entity in poiEntities.values {
            (entity.children.first as? ModelEntity)?.model?.materials = [crystal]
        }
    }

    private func fetchWeatherIfNeeded(at coordinate: CLLocationCoordinate2D) {
        if let last = lastWeatherFetch, Date().timeIntervalSince(last) < 15 * 60 { return }
        lastWeatherFetch = .now
        Task { [weak self] in
            do {
                let weather = try await WeatherService.fetch(at: coordinate)
                self?.game?.liveWeather = weather
            } catch {
                // Try again in 2 minutes; the manual weather menu keeps working.
                self?.lastWeatherFetch = Date().addingTimeInterval(-13 * 60)
            }
        }
    }

    private func updateAmbience(game: GameState) {
        let cell = WorldGrid.cell(displayed)
        var green = 0
        for dx in -4...4 { for dy in -4...4 where greenCells.contains(cell &+ SIMD2(Int32(dx), Int32(dy))) { green += 1 } }
        AudioManager.shared.setAmbience(
            dark: game.activePreset.isDark,
            nature: green > 18,
            rain: game.activeWeather == .rain,
            windy: (game.liveWeather?.windSpeed ?? 0) > 25
        )
    }

    // MARK: - Tile streaming

    private func networkChanged(available: Bool) {
        let regained = available && !networkAvailable
        networkAvailable = available
        guard regained else { return }
        // Retry failed tiles right away when the connection comes back.
        for (key, state) in tiles {
            if case .failed(let attempts, _, let error) = state {
                tiles[key] = .failed(attempts: attempts, retryAt: .distantPast, error: error)
            }
        }
        streamTimer = 10
        if let game, !(game.liveWeather != nil) { lastWeatherFetch = nil }
    }

    private func streamTiles(game: GameState, location: LocationService) {
        guard let projection = location.projection else { return }
        let here = projection.coordinate(planar: displayed)
        let center = TileKey(containing: here)
        var desired: [TileKey] = []
        for dy in -1...1 { for dx in -1...1 { desired.append(TileKey(x: center.x + dx, y: center.y + dy)) } }

        // Nearest tiles first (the centre tile is always first in line).
        func distance(_ t: TileKey) -> Double { simd_distance(projection.planar(t.center), displayed) }
        let now = Date()
        let candidates = desired.filter { key in
            switch tiles[key] {
            case nil: return true
            case .failed(_, let retryAt, _): return retryAt <= now
            default: return false
            }
        }.sorted { distance($0) < distance($1) }

        let centerSaved = OSMService.hasCache(for: center)
        // No saved street here yet: one tiny preview query races the centre tile, so Lorna has a
        // street in seconds. It takes one of the two network slots.
        if !previewRequested, networkAvailable, !centerSaved, netInFlight < Self.maxNetwork {
            if case .loaded = tiles[center] {} else { loadPreview(around: here, desired: desired, projection: projection) }
        }

        for key in candidates {
            if OSMService.hasCache(for: key) {
                // Saved tiles load straight from disk, whatever the network is doing.
                guard diskInFlight < Self.maxDisk else { continue }
                load(key, projection: projection, network: false)
            } else {
                guard networkAvailable, netInFlight < Self.maxNetwork else { continue }
                load(key, projection: projection, network: true)
            }
        }

        prune(center: center)
        publishStatus(game: game, desired: desired, locating: !location.hasFix)
        backgroundFetch(center: center, desired: desired, location: location)
    }

    /// Idle-time network work, one request at a time and only when nothing visible is waiting:
    /// refresh old saved tiles, then save the tiles ahead of the player to disk so the next
    /// streets appear instantly when she walks into them.
    private func backgroundFetch(center: TileKey, desired: [TileKey], location: LocationService) {
        guard networkAvailable, !backgroundFetchBusy, netInFlight == 0 else { return }
        let settled = desired.allSatisfy { key in
            switch tiles[key] {
            case .loaded, .failed: return true
            default: return false
            }
        }
        guard settled else { return }

        var target: TileKey?
        if let stale = staleTiles.first(where: { desired.contains($0) }) {
            target = stale
            staleTiles.remove(stale)
        } else if location.isMoving, simd_length(visualVelocity) > 0.5 {
            // The row of tiles just beyond the loaded ring, in the direction of travel.
            let v = simd_normalize(visualVelocity)
            let sx = abs(v.x) > 0.38 ? (v.x > 0 ? 1 : -1) : 0
            let sy = abs(v.y) > 0.38 ? (v.y > 0 ? -1 : 1) : 0 // tile y grows southwards
            var ahead: [TileKey] = []
            for offset in -1...1 {
                if sx != 0 { ahead.append(TileKey(x: center.x + 2 * sx, y: center.y + offset + sy)) }
                if sy != 0 { ahead.append(TileKey(x: center.x + offset + sx, y: center.y + 2 * sy)) }
            }
            target = ahead.first { !prefetchSkipped.contains($0) && !OSMService.cachedIfFresh(tile: $0) }
        }
        guard let target else { return }
        backgroundFetchBusy = true
        Task { [weak self] in
            do {
                try await OSMService.storeOnDisk(tile: target)
            } catch {
                self?.prefetchSkipped.insert(target)
            }
            self?.backgroundFetchBusy = false
        }
    }

    /// The warm-start frame was far from the real position: start the world over in the new frame.
    private func resetWorld(epoch: Int) {
        worldEpoch = epoch
        for case .loaded(let chunk, _) in tiles.values { chunk.entity.removeFromParent() }
        for chunk in previews.values { chunk.entity.removeFromParent() }
        tiles = [:]
        previews = [:]
        staleTiles = []
        previewRequested = false
        hasPlacedPlayer = false
        displayed = .zero
        cameraTarget = nil
        mergeDirty = true
        streamTimer = 10
    }

    private func load(_ key: TileKey, projection: GeoProjection, network: Bool) {
        let attempts: Int
        if case .failed(let a, _, _) = tiles[key] { attempts = a } else { attempts = 0 }
        tiles[key] = .loading
        if network { netInFlight += 1 } else { diskInFlight += 1 }
        let epoch = worldEpoch
        Task { [weak self] in
            do {
                // Disk read + JSON parse and the geometry build both run off the main thread.
                let result = try await OSMService.fetch(tile: key)
                let geometry = await Task.detached(priority: .userInitiated) {
                    WorldBuilder.build(result.data, tile: key, projection: projection)
                }.value
                guard let self else { return }
                let preset = self.appliedPreset ?? .sunset
                let chunk = await WorldChunk.make(tile: key, geometry: geometry, preset: preset, wet: self.appliedWeather == .rain)
                if network { self.netInFlight -= 1 } else { self.diskInFlight -= 1 }
                // The player may have walked away (or the frame changed) while it loaded.
                guard epoch == self.worldEpoch, case .loading = self.tiles[key] else { return }
                if result.stale { self.staleTiles.insert(key) }
                chunk.apply(self.appliedPreset ?? preset, wet: self.appliedWeather == .rain)
                self.worldRoot.addChild(chunk.entity)
                if let preview = self.previews.removeValue(forKey: key) {
                    // Same-frame swap: the detailed tile replaces its stand-in with no gap.
                    preview.entity.removeFromParent()
                } else {
                    self.fadeIn(chunk.entity)
                }
                self.tiles[key] = .loaded(chunk, fromCache: result.fromCache)
                self.mergeDirty = true
                self.streamTimer = 10
            } catch {
                guard let self else { return }
                if network { self.netInFlight -= 1 } else { self.diskInFlight -= 1 }
                guard epoch == self.worldEpoch, case .loading = self.tiles[key] else { return }
                let message = (error as? OSMError)?.userMessage ?? (error as? URLError).map { _ in OSMError.offline.userMessage } ?? "Map unavailable"
                // Exponential backoff: 4 s, 8 s, 16 s … capped at 2 minutes.
                let delay = min(120, 4 * pow(2, Double(attempts)))
                self.tiles[key] = .failed(attempts: attempts + 1, retryAt: Date().addingTimeInterval(delay), error: message)
            }
        }
    }

    private func loadPreview(around here: CLLocationCoordinate2D, desired: [TileKey], projection: GeoProjection) {
        previewRequested = true
        netInFlight += 1
        let epoch = worldEpoch
        Task { [weak self] in
            let data = try? await OSMService.fetchPreview(around: here)
            self?.netInFlight -= 1
            guard let data else {
                // Allow one more try after a pause instead of hammering the servers.
                try? await Task.sleep(for: .seconds(6))
                if self?.worldEpoch == epoch { self?.previewRequested = false }
                return
            }
            for key in desired {
                guard let self, epoch == self.worldEpoch else { return }
                if case .loaded = self.tiles[key] { continue }
                let geometry = await Task.detached(priority: .userInitiated) {
                    WorldBuilder.build(data, tile: key, projection: projection)
                }.value
                guard geometry.hasContent else { continue }
                let preset = self.appliedPreset ?? .sunset
                let chunk = await WorldChunk.make(tile: key, geometry: geometry, preset: preset, wet: self.appliedWeather == .rain)
                // The full tile may have won the race meanwhile.
                guard epoch == self.worldEpoch else { return }
                if case .loaded = self.tiles[key] { continue }
                chunk.apply(self.appliedPreset ?? preset, wet: self.appliedWeather == .rain)
                self.worldRoot.addChild(chunk.entity)
                self.previews[key] = chunk
                self.fadeIn(chunk.entity)
                self.mergeDirty = true
            }
        }
    }

    private func fadeIn(_ entity: Entity) {
        entity.components.set(OpacityComponent(opacity: 0))
        fading.append((entity, 0))
    }

    private func updateFades(dt: Float) {
        guard !fading.isEmpty else { return }
        for i in fading.indices.reversed() {
            fading[i].t += dt / 0.6
            let t = min(1, fading[i].t)
            if t >= 1 {
                fading[i].entity.components.remove(OpacityComponent.self)
                fading.remove(at: i)
            } else {
                fading[i].entity.components.set(OpacityComponent(opacity: t * t * (3 - 2 * t)))
            }
        }
    }

    private func prune(center: TileKey) {
        for key in previews.keys where abs(key.x - center.x) > 2 || abs(key.y - center.y) > 2 {
            previews.removeValue(forKey: key)?.entity.removeFromParent()
        }
        let far = tiles.keys.filter { abs($0.x - center.x) > 2 || abs($0.y - center.y) > 2 }
        guard !far.isEmpty else { return }
        for key in far {
            if case .loaded(let chunk, _) = tiles[key] { chunk.entity.removeFromParent() }
            tiles[key] = nil
            staleTiles.remove(key)
        }
        mergeDirty = true
    }

    private func publishStatus(game: GameState, desired: [TileKey], locating: Bool) {
        var status = WorldStatus()
        status.locating = locating
        status.total = desired.count
        status.previewReady = !previews.isEmpty
        var failures: [String] = []
        for key in desired {
            switch tiles[key] {
            case .loaded(_, let cached):
                status.loaded += 1
                if cached { status.fromCache = true }
            case .failed(_, _, let error): failures.append(error)
            default: break
            }
        }
        if status.loaded == status.total {
            status.phase = .ready
        } else if !networkAvailable {
            status.phase = .offline
        } else if let error = failures.first, status.loaded + failures.count == status.total {
            status.phase = .failed(error)
        } else {
            status.phase = .loading
        }
        if status != game.worldStatus { game.worldStatus = status }
    }

    private func mergeTiles() {
        mergeDirty = false
        var samples: [SIMD2<Double>] = []
        var occ: [SIMD2<Int32>: Float] = [:]
        var greens: Set<SIMD2<Int32>> = []
        var places: [PlacedPOI] = []
        for chunk in visibleChunks {
            samples += chunk.geometry.roadSamples
            occ.merge(chunk.geometry.occluders) { max($0, $1) }
            greens.formUnion(chunk.geometry.greenCells)
            places += chunk.geometry.pois
        }
        roadSamples = samples
        occluders = occ
        greenCells = greens
        pois = places
        syncPOIEntities()
    }

    // MARK: - Places (POIs)

    private func syncPOIEntities() {
        let ids = Set(pois.map(\.id))
        for (id, entity) in poiEntities where !ids.contains(id) {
            entity.removeFromParent()
            poiEntities[id] = nil
        }
        let material = WorldMaterials.shared.material(.poiCrystal, preset: appliedPreset ?? .sunset)
        for poi in pois where poiEntities[poi.id] == nil {
            let holder = Entity()
            let gem = ModelEntity(mesh: .generateBox(size: 0.7, cornerRadius: 0.04), materials: [material])
            gem.orientation = simd_quatf(angle: .pi / 4, axis: simd_normalize(SIMD3<Float>(1, 0, 1)))
            gem.scale = [1, 1.5, 1]
            gem.components.set(DynamicLightShadowComponent(castsShadow: false))
            holder.addChild(gem)
            holder.position = GeoProjection.world(poi.position, y: 2.2)
            poiRoot.addChild(holder)
            poiEntities[poi.id] = holder
        }
    }

    private func animatePOIs(dt: Float) {
        guard !poiEntities.isEmpty, let game else { return }
        for poi in pois {
            guard let entity = poiEntities[poi.id] else { continue }
            let phase = clock * 1.4 + Float(poi.id % 97)
            entity.position.y = 2.2 + 0.18 * sin(phase)
            entity.orientation = simd_quatf(angle: clock * 0.8 + Float(poi.id % 13), axis: [0, 1, 0])
            let isTarget = game.activeRoute?.current?.id == poi.id
            let dim = game.visitedToday(poi)
            let s: Float = isTarget ? 1.35 + 0.1 * sin(clock * 4) : (dim ? 0.6 : 1)
            entity.scale = SIMD3(repeating: s)
        }
    }

    private func updatePOIInfo(game: GameState) {
        var infos: [POIInfo] = []
        for poi in pois {
            let d = simd_distance(poi.position, displayed)
            guard d < 900 else { continue }
            let delta = poi.position - displayed
            let bearing = (atan2(delta.x, delta.y) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
            infos.append(POIInfo(poi: poi, distance: d, bearing: bearing))
            if d < GameState.discoveryRange, game.encounter == nil, game.storyRun == nil {
                game.visit(poi)
            }
        }
        infos.sort { $0.distance < $1.distance }
        let trimmed = Array(infos.prefix(40))
        if trimmed.map(\.id) != game.nearbyPOIs.map(\.id) || zip(trimmed, game.nearbyPOIs).contains(where: { abs($0.distance - $1.distance) > 2 }) {
            game.nearbyPOIs = trimmed
        }
    }

    // MARK: - Spirits

    private func maintainSpirits(game: GameState) {
        let spiritNight = game.events.contains(.spiritNight)
        if !spawnedInitial {
            guard game.worldStatus.hasWorld || game.worldStatus.phase == .offline || clock > 12 else { return }
            spawnedInitial = true
            spawn(.lanternWisp, distance: 30...42)
            spawn(randomKind(game: game, spiritNight: spiritNight), distance: 70...95)
            spawn(randomKind(game: game, spiritNight: spiritNight), distance: 95...130)
            return
        }
        let target = spiritNight ? 6 : 4
        if spirits.count < target {
            spawn(randomKind(game: game, spiritNight: spiritNight), distance: 60...160)
            AudioManager.shared.play(.spiritAlert, volume: 0.5)
        }
        // Spirits left far behind drift back into the player's neighbourhood.
        for spirit in spirits where simd_distance(spirit.position, displayed) > 400 {
            if let p = spawnPoint(distance: 60...150) { spirit.place(at: p) }
        }
    }

    private func randomKind(game: GameState, spiritNight: Bool) -> SpiritKind {
        let nearWater = pois.contains { $0.category == .fountain && simd_distance($0.position, displayed) < 250 }
        return SpiritKind.spawnPool(isNight: game.activePreset.isDark, nearWater: nearWater, spiritNight: spiritNight)
            .randomElement() ?? .lanternWisp
    }

    private func spawn(_ kind: SpiritKind, distance: ClosedRange<Double>) {
        guard let point = spawnPoint(distance: distance) else { return }
        let spirit = SpiritEntity(kind: kind, home: point)
        spirits.append(spirit)
        root.addChild(spirit.root)
    }

    /// A street point at the requested distance, or a random point if no map is available.
    private func spawnPoint(distance: ClosedRange<Double>) -> SIMD2<Double>? {
        let candidates = roadSamples.filter { distance.contains(simd_distance($0, displayed)) }
        let occupied = spirits.map(\.position)
        let free = candidates.filter { c in occupied.allSatisfy { simd_distance($0, c) > 25 } }
        if let pick = free.randomElement() ?? candidates.randomElement() { return pick }
        let angle = Double.random(in: 0..<(2 * .pi))
        let r = Double.random(in: distance)
        return displayed + SIMD2(cos(angle), sin(angle)) * r
    }

    private func calm(spiritID: UUID) {
        guard let index = spirits.firstIndex(where: { $0.id == spiritID }) else { return }
        spirits[index].root.removeFromParent()
        spirits.remove(at: index)
        game?.spirits.removeAll { $0.id == spiritID }
        // maintainSpirits refills the street over the next seconds.
    }

    // MARK: - Encounter stage

    private func makeStageSource() -> EncounterStageSource {
        let world = Entity()
        let origin = GeoProjection.world(displayed)
        for chunk in visibleChunks {
            world.addChild(chunk.entity.clone(recursive: true))
        }
        let groundClone = ground.clone(recursive: false)
        world.addChild(groundClone)
        return EncounterStageSource(
            world: world,
            origin: origin,
            forwardYaw: lornaYaw + .pi,
            preset: appliedPreset ?? .sunset,
            weather: appliedWeather ?? .clear,
            sunAzimuth: sunAzimuth,
            sunElevation: sunElevation
        )
    }

    // MARK: - Player markers

    private func buildPlayerMarkers() {
        var wedge = MeshBuilder()
        let segments = 10
        let spread: Float = 0.42, length: Float = 4.2
        for i in 0..<segments {
            let a0 = -spread + 2 * spread * Float(i) / Float(segments)
            let a1 = -spread + 2 * spread * Float(i + 1) / Float(segments)
            // UV origin is bottom-left: the apex samples the opaque top of the gradient.
            wedge.addTriangle([0, 0.08, 0], [sin(a0) * length, 0.08, cos(a0) * length], [sin(a1) * length, 0.08, cos(a1) * length],
                              normal: [0, 1, 0], uv: (SIMD2(0.5, 1), SIMD2(0, 0), SIMD2(1, 0)))
        }
        var wedgeMaterial = UnlitMaterial(color: UIColor(hex: 0x4FA3F7))
        if let image = Self.wedgeImage(), let tex = try? TextureResource(image: image, options: .init(semantic: .color)) {
            wedgeMaterial.color = .init(tint: .white, texture: .init(tex))
        }
        wedgeMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.85))
        wedgeMaterial.faceCulling = .none
        headingWedge.model = ModelComponent(mesh: wedge.makeMesh(name: "wedge") ?? .generatePlane(width: 1, depth: 1), materials: [wedgeMaterial])
        headingWedge.components.set(DynamicLightShadowComponent(castsShadow: false))
        root.addChild(headingWedge)

        var ring = MeshBuilder()
        let points = (0...32).map { i -> SIMD2<Float> in
            let a = Float(i) / 32 * 2 * .pi
            return SIMD2(cos(a), sin(a)) * 0.42
        }
        ring.addRibbon(points, width: 0.05, y: 0.09, roundJoins: false)
        var ringMaterial = UnlitMaterial(color: UIColor(hex: 0xFFF4E0))
        ringMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.85))
        ringMaterial.faceCulling = .none
        footRing.model = ModelComponent(mesh: ring.makeMesh(name: "footRing") ?? .generatePlane(width: 1, depth: 1), materials: [ringMaterial])
        footRing.components.set(DynamicLightShadowComponent(castsShadow: false))
        root.addChild(footRing)
    }

    private static func wedgeImage() -> CGImage? {
        UIGraphicsImageRenderer(size: CGSize(width: 32, height: 64)).image { ctx in
            let colors = [UIColor(hex: 0x4FA3F7, alpha: 0.75).cgColor, UIColor(hex: 0x3B7BD4, alpha: 0).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: 64), options: [])
            }
        }.cgImage
    }
}
