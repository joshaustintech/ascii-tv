import Foundation

/// Where the globe sits on screen, in pixels, and how the camera is tilted.
public struct GlobeLayout: Equatable, Sendable {
    public var widthPx: Int
    public var heightPx: Int
    public var centreX: Double
    public var centreY: Double
    public var radius: Double
    /// The camera looks straight at this latitude, so the northern continents are not squashed at the top.
    public var tiltDeg: Double

    public init(widthPx: Int, heightPx: Int, centreX: Double, centreY: Double, radius: Double, tiltDeg: Double = 18) {
        self.widthPx = widthPx
        self.heightPx = heightPx
        self.centreX = centreX
        self.centreY = centreY
        self.radius = radius
        self.tiltDeg = tiltDeg
    }

    /// A globe centred on the screen, leaving room above and below for labels.
    public static func centred(widthPx: Int, heightPx: Int) -> GlobeLayout {
        GlobeLayout(widthPx: widthPx, heightPx: heightPx, centreX: Double(widthPx) / 2,
                    centreY: Double(heightPx) / 2, radius: Double(heightPx) * 0.43)
    }

    /// Pixel position of a place for the given centre meridian, or nil when it is on the far side
    /// (or so close to the edge of the disc that a label would float off the globe).
    public func project(lat: Double, lon: Double, centreLonDeg: Double) -> (x: Double, y: Double)? {
        let rad = Double.pi / 180
        let rl = (lon - centreLonDeg) * rad
        let ex = cos(lat * rad) * sin(rl), ey = sin(lat * rad), ez = cos(lat * rad) * cos(rl)
        let st = sin(tiltDeg * rad), ct = cos(tiltDeg * rad)
        let y = ey * ct - ez * st, z = ey * st + ez * ct
        guard z > 0.08 else { return nil }
        return (centreX + ex * radius, centreY - y * radius)
    }
}

/// Turns wall-clock time into the globe's rotation. The rotation is quantised to land-mask columns
/// (half a degree), because nothing on screen changes in between: that is what lets the app sleep.
public enum GlobeClock {
    /// Mask column facing the viewer. Decreases over time so the surface travels west to east.
    public static func centreColumn(at date: Date, period: TimeInterval) -> Int {
        let phase = date.timeIntervalSince1970.truncatingRemainder(dividingBy: period) / period
        return (LandMask.cols - Int(phase * Double(LandMask.cols))) % LandMask.cols
    }

    public static func longitude(ofColumn column: Int) -> Double { Double(column) * 0.5 - 180 }

    /// The next instant at which `centreColumn` changes.
    public static func nextChange(after date: Date, period: TimeInterval) -> Date {
        let step = period / Double(LandMask.cols)
        let t = date.timeIntervalSince1970
        return Date(timeIntervalSince1970: ((t / step).rounded(.down) + 1) * step)
    }
}
