import Foundation
import GlobeCore
import MusicKit

/// Loops the user's chosen Apple Music library playlist.
///
/// Needs a real Apple TV signed in to an Apple Music subscription, and the MusicKit app service enabled for
/// the app's bundle ID in the developer portal. The simulator has neither a music library nor playback,
/// so there it offers sample playlist names and plays nothing.
@MainActor
final class MusicController: ObservableObject {
    struct PlaylistRef: Identifiable, Hashable {
        let id: String
        let name: String
    }

    @Published private(set) var playlists: [PlaylistRef] = []
    @Published private(set) var status = ""

    private let store: SettingsStore
    private var library: [String: Playlist] = [:]
    private var libraryLoaded = false

    private static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    init(store: SettingsStore) {
        self.store = store
    }

    var selectedID: String? { store.settings.playlistID }

    /// Asks for Apple Music access (first time only) and reads the user's library playlists.
    func loadLibrary() async {
        guard !libraryLoaded else { return }
        if Self.isSimulator {
            playlists = ["Late Night Ambient", "Orbital Jazz", "Focus Loops"].map { PlaylistRef(id: "sim." + $0, name: $0) }
            status = "Simulator: sample playlists only, no sound."
            libraryLoaded = true
            return
        }
        status = "Loading your playlists..."
        guard await MusicAuthorization.request() == .authorized else {
            status = "Apple Music access is off. Allow it in Settings > Apps > ASCII TV."
            return
        }
        do {
            let items = try await MusicLibraryRequest<Playlist>().response().items
            library = Dictionary(items.map { ($0.id.rawValue, $0) }, uniquingKeysWith: { first, _ in first })
            playlists = items.map { PlaylistRef(id: $0.id.rawValue, name: $0.name) }
            status = playlists.isEmpty ? "No playlists in your Apple Music library." : ""
            libraryLoaded = true
        } catch {
            status = "Could not load playlists: \(error.localizedDescription)"
        }
    }

    /// Saves the choice and starts (or, for nil, stops) playback.
    func choose(_ playlist: PlaylistRef?) {
        store.settings.playlistID = playlist?.id
        store.settings.playlistName = playlist?.name
        Task { await applySelection() }
    }

    /// Call at launch and whenever the app comes back to the front: restarts the saved playlist if it is not playing.
    func resume() async {
        guard store.settings.playlistID != nil else { return }
        if !Self.isSimulator, ApplicationMusicPlayer.shared.state.playbackStatus == .playing { return }
        await loadLibrary()
        await applySelection()
    }

    private func applySelection() async {
        guard !Self.isSimulator else { return }
        let player = ApplicationMusicPlayer.shared
        guard let id = store.settings.playlistID else {
            player.stop()
            status = ""
            return
        }
        guard let playlist = library[id] else {
            if libraryLoaded { status = "\"\(store.settings.playlistName ?? "The saved playlist")\" is no longer in your library." }
            return
        }
        do {
            player.queue = [playlist]
            player.state.repeatMode = .all     // loop the whole playlist forever
            try await player.play()
            status = "Looping \(playlist.name)."
        } catch {
            status = "Could not play \(playlist.name): \(error.localizedDescription)"
        }
    }
}
