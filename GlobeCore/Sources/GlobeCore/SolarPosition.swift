import Foundation

/// The point on Earth where the sun is directly overhead.
public struct SubsolarPoint: Equatable, Sendable {
    /// Degrees, north positive (the solar declination).
    public var lat: Double
    /// Degrees, east positive, -180...180.
    public var lon: Double

    public init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }
}

public enum SolarPosition {
    /// Low-precision solar position (Astronomical Almanac), good to about 0.01 degrees: far finer than one
    /// character cell. `Date` is an absolute instant, so the result is right in any device time zone.
    public static func subsolarPoint(at date: Date) -> SubsolarPoint {
        let rad = Double.pi / 180
        let n = date.timeIntervalSince1970 / 86400.0 + 2440587.5 - 2451545.0   // days since J2000
        let meanLongitude = 280.460 + 0.9856474 * n
        let g = (357.528 + 0.9856003 * n) * rad                                  // mean anomaly
        let lambda = (meanLongitude + 1.915 * sin(g) + 0.020 * sin(2 * g)) * rad // ecliptic longitude
        let eps = (23.439 - 0.0000004 * n) * rad                                 // obliquity
        let dec = asin(sin(eps) * sin(lambda))
        let ra = atan2(cos(eps) * sin(lambda), cos(lambda)) / rad
        let gmst = 280.46061837 + 360.98564736629 * n                            // Greenwich sidereal angle
        var lon = (ra - gmst).truncatingRemainder(dividingBy: 360)
        if lon > 180 { lon -= 360 }
        if lon < -180 { lon += 360 }
        return SubsolarPoint(lat: dec / rad, lon: lon)
    }

    /// True when the sun is above the horizon at the given place.
    public static func isDaylight(lat: Double, lon: Double, sun: SubsolarPoint) -> Bool {
        let rad = Double.pi / 180
        return sin(lat * rad) * sin(sun.lat * rad)
            + cos(lat * rad) * cos(sun.lat * rad) * cos((lon - sun.lon) * rad) > 0
    }
}
