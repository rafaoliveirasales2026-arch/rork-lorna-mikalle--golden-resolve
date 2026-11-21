import CoreLocation
import simd

/// Local flat-earth projection around a fixed origin.
/// Planar space: x = metres east, y = metres north.
/// World (RealityKit) space: x = east, y = up, z = -north (so -Z faces north).
nonisolated struct GeoProjection: Sendable {
    let origin: CLLocationCoordinate2D
    private let metersPerDegLat: Double
    private let metersPerDegLon: Double

    init(origin: CLLocationCoordinate2D) {
        self.origin = origin
        let lat = origin.latitude * .pi / 180
        metersPerDegLat = 111_132.92 - 559.82 * cos(2 * lat) + 1.175 * cos(4 * lat)
        metersPerDegLon = 111_412.84 * cos(lat) - 93.5 * cos(3 * lat)
    }

    func planar(_ c: CLLocationCoordinate2D) -> SIMD2<Double> {
        SIMD2((c.longitude - origin.longitude) * metersPerDegLon,
              (c.latitude - origin.latitude) * metersPerDegLat)
    }

    func coordinate(planar p: SIMD2<Double>) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: origin.latitude + p.y / metersPerDegLat,
                               longitude: origin.longitude + p.x / metersPerDegLon)
    }

    static func world(_ p: SIMD2<Double>, y: Float = 0) -> SIMD3<Float> {
        SIMD3(Float(p.x), y, Float(-p.y))
    }

    static func planar(world w: SIMD3<Float>) -> SIMD2<Double> {
        SIMD2(Double(w.x), Double(-w.z))
    }
}

extension Double {
    nonisolated var compassName: String {
        let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let normalized = (self.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return names[Int((normalized + 22.5) / 45) % 8]
    }
}
