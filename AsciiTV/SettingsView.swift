import GlobeCore
import SwiftUI

/// In-app settings: labelled places, the Apple Music playlist, and how fast the globe turns.
struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var music: MusicController
    @State private var path: [Route] = []

    enum Route: Hashable {
        case add
        case edit(UUID)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(store.settings.points) { point in
                        NavigationLink(value: Route.edit(point.id)) {
                            HStack {
                                Text(point.label)
                                Spacer()
                                Text(Self.coordinates(point)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    NavigationLink(value: Route.add) { Label("Add a place", systemImage: "plus") }
                } header: {
                    Text("Places")
                } footer: {
                    Text("Each place is marked on the globe while it faces you. When labels would collide, places higher in this list keep theirs.")
                }

                Section {
                    choiceRow("None", selected: music.selectedID == nil) { music.choose(nil) }
                    ForEach(music.playlists) { playlist in
                        choiceRow(playlist.name, selected: music.selectedID == playlist.id) { music.choose(playlist) }
                    }
                    if !music.status.isEmpty {
                        Text(music.status).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Apple Music playlist (plays on loop)")
                }

                Section("Globe speed") {
                    ForEach(GlobeSettings.rotationPeriods, id: \.self) { period in
                        choiceRow(Self.describe(period), selected: store.settings.rotationPeriod == period) {
                            store.settings.rotationPeriod = period
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .add: PlaceEditor(store: store, existing: nil)
                case .edit(let id): PlaceEditor(store: store, existing: store.settings.points.first { $0.id == id })
                }
            }
        }
        .task { await music.loadLibrary() }
    }

    private func choiceRow(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if selected { Image(systemName: "checkmark") }
            }
        }
    }

    private static func coordinates(_ p: GeoPoint) -> String {
        String(format: "%.2f°%@  %.2f°%@", abs(p.lat), p.lat >= 0 ? "N" : "S", abs(p.lon), p.lon >= 0 ? "E" : "W")
    }

    private static func describe(_ period: TimeInterval) -> String {
        period < 3600 ? "One turn every \(Int(period / 60)) min" : "One turn every hour"
    }
}

private struct PlaceEditor: View {
    @ObservedObject var store: SettingsStore
    let existing: GeoPoint?
    @State private var label: String
    @State private var latText: String
    @State private var lonText: String
    @State private var problem: String?
    @Environment(\.dismiss) private var dismiss

    init(store: SettingsStore, existing: GeoPoint?) {
        self.store = store
        self.existing = existing
        _label = State(initialValue: existing?.label ?? "")
        _latText = State(initialValue: existing.map { String($0.lat) } ?? "")
        _lonText = State(initialValue: existing.map { String($0.lon) } ?? "")
    }

    var body: some View {
        Form {
            Section {
                // The standard tvOS keyboard is used for the numbers too: it shows digits, "." and "-" on one
                // page, while the numeric keyboard hides "." and "-" on a second page.
                TextField("Label", text: $label)
                TextField("Latitude, e.g. 35.68 (south is negative)", text: $latText)
                TextField("Longitude, e.g. 139.69 (west is negative)", text: $lonText)
            } footer: {
                if let problem { Text(problem).foregroundStyle(.red) }
            }
            Section {
                Button("Save", action: save)
                if existing != nil {
                    Button("Delete this place", role: .destructive) {
                        store.settings.points.removeAll { $0.id == existing?.id }
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(existing == nil ? "New place" : "Edit place")
        .onChange(of: [label, latText, lonText]) { problem = nil }
    }

    private func save() {
        let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { problem = "Give the place a label."; return }
        guard let lat = Self.number(latText), (-90...90).contains(lat) else {
            problem = "Latitude must be a number from -90 to 90."; return
        }
        guard let lon = Self.number(lonText), (-180...180).contains(lon) else {
            problem = "Longitude must be a number from -180 to 180."; return
        }
        if let existing, let i = store.settings.points.firstIndex(where: { $0.id == existing.id }) {
            store.settings.points[i] = GeoPoint(id: existing.id, label: name, lat: lat, lon: lon)
        } else {
            store.settings.points.append(GeoPoint(label: name, lat: lat, lon: lon))
        }
        dismiss()
    }

    private static func number(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }
}
