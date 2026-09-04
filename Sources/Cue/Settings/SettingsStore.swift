import Foundation
import Observation

/// Everything the user has chosen, and the only thing in Cue that persists
/// across launches besides the keychain.
///
/// `UserDefaults` rather than a file: these are preferences, they are small,
/// and `defaults read com.cue.app` is a diagnostic worth being able to run.
/// Nothing sensitive lives here — tokens and cookies are in the keychain, and
/// the pinned tiles are titles the user chose to pin.
@Observable
final class SettingsStore {
    /// The grid is three by three. Not configurable: nine is the number of
    /// things a person can aim at without reading, and the moment it is a
    /// setting the layout has to work at every value it can take.
    static let tileCount = 9

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        unofficialProviderEnabled = defaults.bool(forKey: Key.unofficialProviderEnabled)
        closesAfterOpening = defaults.object(forKey: Key.closesAfterOpening) as? Bool ?? true
        autoFillsEmptyTiles = defaults.object(forKey: Key.autoFillsEmptyTiles) as? Bool ?? true
        pinnedTiles = Self.loadPinnedTiles(from: defaults)
        hotKey = Self.loadHotKey(from: defaults)

        showsMiniPlayer = defaults.object(forKey: Key.showsMiniPlayer) as? Bool ?? true

        let storedDestination = defaults.string(forKey: Key.playbackDestination)
        playbackDestination = storedDestination.flatMap(PlaybackDestination.init(rawValue:)) ?? .inApp
    }

    /// Whether the plaque appears in the corner of the screen while playing.
    ///
    /// On, because with the player window parked off screen it is the only
    /// thing that says Cue is playing at all — and the only way to pause
    /// without summoning something.
    var showsMiniPlayer: Bool {
        didSet {
            defaults.set(showsMiniPlayer, forKey: Key.showsMiniPlayer)
            onMiniPlayerChange?()
        }
    }

    /// Raised when the plaque should be reconsidered.
    var onMiniPlayerChange: (() -> Void)?

    /// Whether picking something plays it in Cue or hands it to the browser.
    ///
    /// In Cue, because that is what the app is for: a panel that sends you to
    /// a browser window you did not ask for has lost you your place in
    /// whatever you were actually doing.
    var playbackDestination: PlaybackDestination {
        didSet { defaults.set(playbackDestination.rawValue, forKey: Key.playbackDestination) }
    }

    /// Raised when the shortcut changes, so it can be re-registered without
    /// this type knowing what a hotkey is.
    var onHotKeyChange: (() -> Void)?

    /// The global shortcut, or `nil` for none.
    ///
    /// `nil` is a real choice rather than an unset value — someone driving Cue
    /// from Shortcuts or a launcher wants no registration at all — which is why
    /// it is stored in a way that can tell "cleared" from "never touched".
    var hotKey: KeyCombination? {
        didSet {
            guard hotKey != oldValue else { return }
            saveHotKey()
            onHotKeyChange?()
        }
    }

    /// Turns the internal YouTube Music backend on.
    ///
    /// Off by default, and it stays off by default: it is a session cookie
    /// replayed against endpoints with no stability promise, and that should be
    /// something someone chose rather than something they got.
    var unofficialProviderEnabled: Bool {
        didSet { defaults.set(unofficialProviderEnabled, forKey: Key.unofficialProviderEnabled) }
    }

    /// Whether picking something dismisses the panel.
    ///
    /// On, because the panel is a means to an end and the end is in another
    /// app. Off is for queueing up several things in a row.
    var closesAfterOpening: Bool {
        didSet { defaults.set(closesAfterOpening, forKey: Key.closesAfterOpening) }
    }

    /// Whether unpinned slots show recent and library items.
    ///
    /// On, because nine empty squares on first launch is a worse first
    /// impression than nine reasonable guesses — and because most people never
    /// pin anything.
    var autoFillsEmptyTiles: Bool {
        didSet { defaults.set(autoFillsEmptyTiles, forKey: Key.autoFillsEmptyTiles) }
    }

    /// Nine slots, in reading order, each either pinned or empty.
    ///
    /// A fixed-length array with holes rather than a compacted list, because a
    /// speed dial's whole value is that the thing in the top-left corner is
    /// still in the top-left corner tomorrow. Removing the fourth tile must
    /// not slide the fifth into its place.
    private(set) var pinnedTiles: [MusicItem?]

    func pin(_ item: MusicItem, at index: Int) {
        guard pinnedTiles.indices.contains(index) else { return }
        // The same thing pinned twice is a wasted slot, and dragging a tile to
        // a new position is expressed as a pin at the destination — so the old
        // position has to give way.
        for (slot, existing) in pinnedTiles.enumerated() where existing?.id == item.id {
            pinnedTiles[slot] = nil
        }
        pinnedTiles[index] = item
        savePinnedTiles()
    }

    func unpin(at index: Int) {
        guard pinnedTiles.indices.contains(index) else { return }
        pinnedTiles[index] = nil
        savePinnedTiles()
    }

    /// The first empty slot, for "pin this" with nowhere specified.
    var firstFreeSlot: Int? {
        pinnedTiles.firstIndex(where: { $0 == nil })
    }

    func isPinned(_ item: MusicItem) -> Bool {
        pinnedTiles.contains { $0?.id == item.id }
    }

    // MARK: - Persistence

    private func savePinnedTiles() {
        // Encoded as an array of optionals so the holes survive the round
        // trip; a dictionary keyed by index would too, but this reads back in
        // one line and cannot disagree with itself about the count.
        guard let data = try? JSONEncoder().encode(pinnedTiles) else { return }
        defaults.set(data, forKey: Key.pinnedTiles)
    }

    private static func loadPinnedTiles(from defaults: UserDefaults) -> [MusicItem?] {
        let empty = [MusicItem?](repeating: nil, count: tileCount)

        guard let data = defaults.data(forKey: Key.pinnedTiles),
              let stored = try? JSONDecoder().decode([MusicItem?].self, from: data)
        else { return empty }

        // Defensive about the count rather than trusting it: a stored array
        // from a build with a different grid size must not crash this one, and
        // an index out of range while drawing the panel is the worst possible
        // place for it.
        var tiles = empty
        for (index, item) in stored.prefix(tileCount).enumerated() {
            tiles[index] = item
        }
        return tiles
    }

    // MARK: - Shortcut persistence

    /// Stored as a list so that absent, empty and set are three distinct
    /// states: no key at all means a fresh install and gets the default, an
    /// empty list means the user cleared it, and one element is a shortcut.
    /// An optional encoded directly could not tell the first two apart.
    private func saveHotKey() {
        let box = hotKey.map { [$0] } ?? []
        guard let data = try? JSONEncoder().encode(box) else { return }
        defaults.set(data, forKey: Key.hotKey)
    }

    private static func loadHotKey(from defaults: UserDefaults) -> KeyCombination? {
        guard let data = defaults.data(forKey: Key.hotKey) else { return .default }
        guard let box = try? JSONDecoder().decode([KeyCombination].self, from: data) else {
            return .default
        }
        return box.first
    }

    private enum Key {
        static let hotKey = "hotKey"
        static let playbackDestination = "playbackDestination"
        static let showsMiniPlayer = "showsMiniPlayer"
        static let unofficialProviderEnabled = "unofficialProviderEnabled"
        static let closesAfterOpening = "closesAfterOpening"
        static let autoFillsEmptyTiles = "autoFillsEmptyTiles"
        static let pinnedTiles = "pinnedTiles"
    }
}
