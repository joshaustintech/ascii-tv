import Foundation

/// A user-defined place on the globe.
public struct GeoPoint: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var label: String
    /// Degrees, north positive, -90...90.
    public var lat: Double
    /// Degrees, east positive, -180...180.
    public var lon: Double

    public init(id: UUID = UUID(), label: String, lat: Double, lon: Double) {
        self.id = id
        self.label = label
        self.lat = max(-90, min(90, lat))
        self.lon = max(-180, min(180, lon))
    }
}

/// Everything the user can change. Stored as one JSON string.
public struct GlobeSettings: Codable, Equatable, Sendable {
    public var points: [GeoPoint]
    /// Apple Music library playlist to loop, or nil for silence.
    public var playlistID: String?
    /// Kept alongside the ID so the choice can be shown before the music library has loaded.
    public var playlistName: String?
    /// Seconds for one full turn of the globe.
    public var rotationPeriod: TimeInterval

    public static let rotationPeriods: [TimeInterval] = [60, 120, 600, 3600]

    public init(points: [GeoPoint] = [], playlistID: String? = nil, playlistName: String? = nil,
                rotationPeriod: TimeInterval = 120) {
        self.points = points
        self.playlistID = playlistID
        self.playlistName = playlistName
        self.rotationPeriod = rotationPeriod
    }

    // Decoded field by field so settings saved by an older version still load when fields are added.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        points = try c.decodeIfPresent([GeoPoint].self, forKey: .points) ?? []
        playlistID = try c.decodeIfPresent(String.self, forKey: .playlistID)
        playlistName = try c.decodeIfPresent(String.self, forKey: .playlistName)
        let period = try c.decodeIfPresent(TimeInterval.self, forKey: .rotationPeriod) ?? 120
        rotationPeriod = Self.rotationPeriods.contains(period) ? period : 120
    }

    public init?(json: String) {
        guard let value = try? JSONDecoder().decode(GlobeSettings.self, from: Data(json.utf8)) else { return nil }
        self = value
    }

    public var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: (try? encoder.encode(self)) ?? Data("{}".utf8), as: UTF8.self)
    }
}

public extension String {
    /// The closest plain-ASCII spelling, since the globe can only draw ASCII: "São Paulo" becomes "Sao Paulo".
    var asciiFolded: String {
        let latin = applyingTransform(.toLatin, reverse: false) ?? self
        let stripped = latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin
        return String(String.UnicodeScalarView(stripped.unicodeScalars.map { $0.value >= 32 && $0.value < 127 ? $0 : "?" }))
    }
}
