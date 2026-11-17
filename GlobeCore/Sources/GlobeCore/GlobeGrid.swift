import Foundation

/// Colours a character can be drawn in. The raw value is the palette index the shader looks up.
public enum Ink: UInt8, CaseIterable, Sendable {
    case black = 0, land, desert, ice, ocean, twilight, amber, white

    public var rgb: (r: Float, g: Float, b: Float) {
        switch self {
        case .black: return (0, 0, 0)
        case .land: return (0.4, 0.85, 0.35)
        case .desert: return (0.9, 0.78, 0.5)
        case .ice: return (0.95, 0.97, 1.0)
        case .ocean: return (0.3, 0.55, 1.0)
        case .twilight: return (1.0, 0.5, 0.2)
        case .amber: return (1.0, 0.82, 0.35)
        case .white: return (1, 1, 1)
        }
    }
}

public struct GlobeCell: Equatable, Sendable {
    public var glyph: Character
    public var ink: Ink
    /// 0...1
    public var brightness: Float
}

@inline(__always) private func ascii(_ s: Unicode.Scalar) -> UInt8 { UInt8(ascii: s) }

/// The globe as a grid of coloured ASCII characters ("Atlas" look: green and tan land, blue ocean,
/// an orange twilight band, amber city lights on the night side, stars behind).
///
/// City lights are fixed places on the ground, projected onto the grid each frame, so each one glides
/// across the globe a cell at a time. (Deciding lights per cell from a hash made them flicker, because a
/// cell looks at a different patch of ground on every step of the rotation.)
///
/// All per-cell trigonometry happens once in `init`. `update` is then an integer offset into the land mask
/// and a cosine-table lookup per cell, so a 4K frame costs about a millisecond of CPU.
public final class GlobeGrid {
    public let cols: Int
    public let rows: Int
    /// Four bytes per cell, row by row: ASCII code, `Ink` raw value, brightness 0...255, unused.
    public private(set) var cells: [UInt8]

    private let mask: LandMask
    private var insideIdx: [Int32] = []
    private var relLon: [Int16] = []      // mask columns relative to the centre meridian
    private var maskRow: [Int16] = []
    private var sinLat: [Float] = []
    private var cosLat: [Float] = []
    private var limb: [Float] = []        // 0 at the edge of the disc, 1 at its centre
    private var absLat: [UInt8] = []

    private let layout: GlobeLayout
    private let cellW: Int
    private let cellH: Int
    private var lightColumn: [Int16] = []
    private var lightSinLat: [Float] = []
    private var lightCosLat: [Float] = []
    public static let cityLightCount = 900

    private static let cosTable: [Float] = (0..<LandMask.cols).map { Float(cos(Double($0) * 0.5 * .pi / 180)) }
    private static let landGlyphs: [UInt8] = [ascii("n"), ascii("m"), ascii("&"), ascii("%"), ascii("#")]

    public init(layout: GlobeLayout, cellW: Int, cellH: Int, mask: LandMask = .naturalEarth) {
        self.mask = mask
        self.layout = layout
        self.cellW = cellW
        self.cellH = cellH
        cols = (layout.widthPx + cellW - 1) / cellW
        rows = (layout.heightPx + cellH - 1) / cellH
        cells = [UInt8](repeating: 0, count: cols * rows * 4)

        let st = sin(layout.tiltDeg * .pi / 180), ct = cos(layout.tiltDeg * .pi / 180)
        for r in 0..<rows {
            for c in 0..<cols {
                let x = ((Double(c) + 0.5) * Double(cellW) - layout.centreX) / layout.radius
                let y = (layout.centreY - (Double(r) + 0.5) * Double(cellH)) / layout.radius
                let d2 = x * x + y * y
                let i = r * cols + c
                if d2 < 1 {
                    let z = sqrt(1 - d2)
                    let ey = y * ct + z * st, ez = -y * st + z * ct
                    let lat = asin(max(-1, min(1, ey)))
                    let lon = atan2(x, ez)
                    insideIdx.append(Int32(i))
                    relLon.append(Int16((lon * 180 / .pi * 2).rounded()))
                    maskRow.append(Int16(min(LandMask.rows - 1, max(0, Int((90 - lat * 180 / .pi) * 2)))))
                    sinLat.append(Float(sin(lat)))
                    cosLat.append(Float(cos(lat)))
                    limb.append(Float(z))
                    absLat.append(UInt8(abs(lat * 180 / .pi)))
                } else {
                    // Backdrop: written once, never touched again.
                    let h = Self.hash(c, r)
                    if d2 < 1.045 { set(i, ascii(":"), .ocean, 0.35) }                          // atmosphere
                    else if h < 3 { set(i, h == 0 ? ascii("+") : ascii("."), .white, 0.45) }    // stars
                }
            }
        }
        placeCityLights()
    }

    /// Scatters the city lights over the land between 60S and 60N. The same places every launch.
    private func placeCityLights() {
        var state: UInt64 = 0x5EED_C17E_5EED_C17E
        func next() -> Double {     // SplitMix64
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
        }
        var attempts = 0
        while lightColumn.count < Self.cityLightCount, attempts < 100_000 {
            attempts += 1
            let lat = asin((next() * 2 - 1) * sin(60 * Double.pi / 180))     // uniform over the sphere's area
            let column = Int(next() * Double(LandMask.cols)) % LandMask.cols
            let row = min(LandMask.rows - 1, Int((90 - lat * 180 / .pi) * 2))
            guard mask.isLand(row: row, col: column) else { continue }
            lightColumn.append(Int16(column))
            lightSinLat.append(Float(sin(lat)))
            lightCosLat.append(Float(cos(lat)))
        }
    }

    public func cell(col: Int, row: Int) -> GlobeCell {
        let i = (row * cols + col) * 4
        return GlobeCell(glyph: Character(UnicodeScalar(max(32, cells[i]))),
                         ink: Ink(rawValue: cells[i + 1]) ?? .black,
                         brightness: Float(cells[i + 2]) / 255)
    }

    /// Redraws the globe with mask column `centreColumn` facing the viewer and the sun over `sun`.
    public func update(centreColumn: Int, sun: SubsolarPoint) {
        let n = LandMask.cols
        let sinDec = Float(sin(sun.lat * .pi / 180)), cosDec = Float(cos(sun.lat * .pi / 180))
        let sunColumn = Int(((sun.lon + 180) * 2).rounded())

        for k in 0..<insideIdx.count {
            let i = Int(insideIdx[k])
            let column = ((Int(relLon[k]) + centreColumn) % n + n) % n
            let row = Int(maskRow[k])
            let land = mask.isLand(row: row, col: column)
            let illum = sinLat[k] * sinDec + cosLat[k] * cosDec * Self.cosTable[((column - sunColumn) % n + n) % n]
            let h = Self.hash(column, row)       // tied to the ground, so the texture travels with the rotation
            let shade = 0.55 + 0.45 * limb[k]
            let twilight = abs(illum) < 0.07

            if land {
                if twilight {
                    set(i, ascii("="), .twilight, 0.75 * shade)
                } else if illum > 0 {
                    let ink: Ink = absLat[k] > 66 ? .ice : (absLat[k] > 14 && absLat[k] < 32 && h > 90 ? .desert : .land)
                    set(i, Self.landGlyphs[Int(h) % 5], ink, (0.5 + 0.5 * illum) * shade)
                } else {
                    set(i, ascii("."), .ocean, 0.5)      // night land: steady, so the continents stay readable
                }
            } else {
                if twilight {
                    set(i, ascii("-"), .twilight, 0.4 * shade)
                } else if illum > 0 {
                    set(i, h < 150 ? ascii("~") : ascii("-"), .ocean, (0.5 + 0.35 * illum) * shade)
                } else {
                    set(i, ascii(" "), .ocean, 0)        // night ocean: dark
                }
            }
        }

        // City lights, drawn over the night side.
        let st = Float(sin(layout.tiltDeg * .pi / 180)), ct = Float(cos(layout.tiltDeg * .pi / 180))
        for l in 0..<lightColumn.count {
            let column = Int(lightColumn[l])
            let illum = lightSinLat[l] * sinDec + lightCosLat[l] * cosDec * Self.cosTable[((column - sunColumn) % n + n) % n]
            guard illum < -0.07 else { continue }
            let d = ((column - centreColumn) % n + n) % n
            let cosRel = Self.cosTable[d], sinRel = Self.cosTable[((d - n / 4) % n + n) % n]   // sin x = cos(x - 90)
            let ex = lightCosLat[l] * sinRel, ey = lightSinLat[l], ez = lightCosLat[l] * cosRel
            let y = ey * ct - ez * st, z = ey * st + ez * ct
            guard z > 0.1 else { continue }                                                    // far side or on the limb
            let col = Int(layout.centreX + Double(ex) * layout.radius) / cellW
            let row = Int(layout.centreY - Double(y) * layout.radius) / cellH
            guard col >= 0, col < cols, row >= 0, row < rows else { continue }
            set(row * cols + col, ascii("*"), .amber, 0.95)
        }
    }

    @inline(__always) private static func hash(_ a: Int, _ b: Int) -> UInt8 {
        var h = UInt32(truncatingIfNeeded: a) &* 73856093 ^ UInt32(truncatingIfNeeded: b) &* 19349663
        h ^= h >> 13; h = h &* 0x5bd1e995; h ^= h >> 15
        return UInt8(truncatingIfNeeded: h)
    }

    @inline(__always) private func set(_ i: Int, _ glyph: UInt8, _ ink: Ink, _ brightness: Float) {
        cells[i * 4] = glyph
        cells[i * 4 + 1] = ink.rawValue
        cells[i * 4 + 2] = UInt8(max(0, min(255, brightness * 255)))
    }
}

/// A coarser text layer drawn over the globe for labels, so they stay readable from the couch.
/// A cell that has been written to hides the globe behind it.
public final class TextGrid {
    public let cols: Int
    public let rows: Int
    /// Four bytes per cell: ASCII code, `Ink` raw value, brightness 0...255, 255 when occupied.
    public private(set) var cells: [UInt8]

    public init(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
        cells = [UInt8](repeating: 0, count: cols * rows * 4)
    }

    public func clear() {
        cells.withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
    }

    /// Writes ASCII text; anything outside the grid is clipped and non-ASCII characters become "?".
    public func put(_ text: String, col: Int, row: Int, ink: Ink, brightness: Float = 1) {
        guard row >= 0, row < rows else { return }
        var c = col
        for u in text.unicodeScalars {
            if c >= 0, c < cols {
                let i = (row * cols + c) * 4
                cells[i] = (u.value >= 32 && u.value < 127) ? UInt8(u.value) : UInt8(ascii: "?")
                cells[i + 1] = ink.rawValue
                cells[i + 2] = UInt8(max(0, min(1, brightness)) * 255)
                cells[i + 3] = 255
            }
            c += 1
        }
    }

    public func text(row: Int) -> String {
        String(String.UnicodeScalarView((0..<cols).map { UnicodeScalar(max(32, cells[(row * cols + $0) * 4])) }))
    }
}
