import Combine
import Foundation
import GlobeCore

/// The user's settings, saved to UserDefaults as one JSON string every time they change.
final class SettingsStore: ObservableObject {
    static let key = "settings"

    @Published var settings: GlobeSettings {
        didSet {
            if settings != oldValue { defaults.set(settings.json, forKey: Self.key) }
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = defaults.string(forKey: Self.key).flatMap(GlobeSettings.init(json:)) ?? GlobeSettings()
    }
}
