import Foundation
import CoreLocation

/// Approximate sun position (NOAA simplified) so the 3D lighting matches the real sky.
nonisolated enum SolarClock {
    struct SunPosition {
        /// Degrees above the horizon.
        let elevation: Double
        /// Degrees clockwise from north.
        let azimuth: Double
    }

    static func sun(at date: Date, coordinate: CLLocationCoordinate2D) -> SunPosition {
        let rad = Double.pi / 180
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let dayOfYear = Double(calendar.ordinality(of: .day, in: .year, for: date) ?? 1)
        let comps = calendar.dateComponents([.hour, .minute, .second], from: date)
        let hourUTC = Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60 + Double(comps.second ?? 0) / 3600

        let gamma = 2 * Double.pi / 365 * (dayOfYear - 1 + (hourUTC - 12) / 24)
        let eqTime = 229.18 * (0.000075 + 0.001868 * cos(gamma) - 0.032077 * sin(gamma)
                               - 0.014615 * cos(2 * gamma) - 0.040849 * sin(2 * gamma))
        let decl = 0.006918 - 0.399912 * cos(gamma) + 0.070257 * sin(gamma)
            - 0.006758 * cos(2 * gamma) + 0.000907 * sin(2 * gamma)
            - 0.002697 * cos(3 * gamma) + 0.00148 * sin(3 * gamma)

        let trueSolarMinutes = hourUTC * 60 + eqTime + 4 * coordinate.longitude
        let hourAngle = (trueSolarMinutes / 4 - 180) * rad
        let lat = coordinate.latitude * rad

        let cosZenith = sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(hourAngle)
        let zenith = acos(max(-1, min(1, cosZenith)))
        let elevation = 90 - zenith / rad

        let azY = sin(hourAngle)
        let azX = cos(hourAngle) * sin(lat) - tan(decl) * cos(lat)
        var azimuth = atan2(azY, azX) / rad + 180
        azimuth = azimuth.truncatingRemainder(dividingBy: 360)
        return SunPosition(elevation: elevation, azimuth: azimuth)
    }
}
