import Foundation

/// Which half-degree squares of the Earth are land. Row 0 touches the north pole; column 0 starts at 180W.
public struct LandMask: Sendable {
    public static let cols = 720
    public static let rows = 360

    private let land: [Bool]

    /// `land` must hold `cols * rows` values, row by row from the north-west corner.
    public init(land: [Bool]) {
        precondition(land.count == Self.cols * Self.rows)
        self.land = land
    }

    @inline(__always) public func isLand(row: Int, col: Int) -> Bool { land[row * Self.cols + col] }

    public func isLand(lat: Double, lon: Double) -> Bool {
        let row = min(Self.rows - 1, max(0, Int((90 - lat) * 2)))
        let col = ((Int(((lon + 180) * 2).rounded(.down)) % Self.cols) + Self.cols) % Self.cols
        return isLand(row: row, col: col)
    }

    /// Real coastlines from Natural Earth 1:50m land (public domain), baked by `Scripts/bake_landmask.py`.
    /// Lakes are not cut out, so the Great Lakes count as land.
    public static let naturalEarth: LandMask = {
        guard let bits = Data(base64Encoded: LandMaskData.naturalEarthBase64), bits.count == cols * rows / 8 else {
            preconditionFailure("LandMaskData.swift is corrupt; regenerate it with Scripts/bake_landmask.py")
        }
        return LandMask(land: (0..<cols * rows).map { bits[$0 / 8] & (0x80 >> UInt8($0 % 8)) != 0 })
    }()
}
