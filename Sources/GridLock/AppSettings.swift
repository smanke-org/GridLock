import AppKit
import Observation

/// App-wide preferences (UserDefaults). Per-desk and per-display settings are not here:
/// they live in the desk library (`DeskStore`).
@Observable
@MainActor
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let confirmQuit = "confirmQuit"
        static let shortcuts = "shortcuts"
    }

    /// "Ask before quitting" in General.
    var confirmQuit: Bool {
        didSet { defaults.set(confirmQuit, forKey: Key.confirmQuit) }
    }

    /// Launch at login is switched on once, the first time the app runs from /Applications.
    var didOfferLaunchAtLogin: Bool {
        get { defaults.bool(forKey: "didOfferLaunchAtLogin") }
        set { defaults.set(newValue, forKey: "didOfferLaunchAtLogin") }
    }

    /// Mirrors AppPresence, so Settings can bind to it and the Dock icon follows at once.
    var showInDock: Bool {
        didSet {
            AppPresence.showInDock = showInDock
            AppPresence.applyDock(keepInFront: NSApp.keyWindow)
        }
    }

    var showInMenuBar: Bool {
        didSet { AppPresence.showInMenuBar = showInMenuBar }
    }

    /// Shortcut id → key. A missing id means "the default"; an id stored as null means the
    /// user cleared it.
    private var shortcuts: [String: HotKey?]

    private init() {
        confirmQuit = defaults.object(forKey: Key.confirmQuit) as? Bool ?? true
        showInDock = AppPresence.showInDock
        showInMenuBar = AppPresence.showInMenuBar
        shortcuts = Self.loadShortcuts(from: defaults)
    }

    func shortcut(_ id: String) -> HotKey? {
        if let stored = shortcuts[id] { return stored }
        return ShortcutCatalog.item(id)?.defaultKey
    }

    func setShortcut(_ id: String, _ key: HotKey?) {
        shortcuts[id] = .some(key)
        if let data = try? JSONEncoder().encode(shortcuts) { defaults.set(data, forKey: Key.shortcuts) }
    }

    /// The shortcut already using `key`, other than `id` itself.
    func owner(of key: HotKey, except id: String) -> ShortcutCatalog.Item? {
        ShortcutCatalog.all.first { $0.id != id && shortcut($0.id).map { $0.keyCode == key.keyCode && $0.modifiers == key.modifiers } == true }
    }

    /// After settings sync replaced values underneath.
    func reload() {
        confirmQuit = defaults.object(forKey: Key.confirmQuit) as? Bool ?? true
        shortcuts = Self.loadShortcuts(from: defaults)
    }

    private static func loadShortcuts(from defaults: UserDefaults) -> [String: HotKey?] {
        guard let data = defaults.data(forKey: Key.shortcuts),
              let decoded = try? JSONDecoder().decode([String: HotKey?].self, from: data) else { return [:] }
        return decoded
    }
}
