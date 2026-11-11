import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A keyboard shortcut: a key code plus Carbon modifier flags, and how to show it.
struct HotKey: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var display: String

    init(keyCode: UInt32, modifiers: UInt32, display: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.display = display
    }

    /// Builds one from a key press, if it has at least one of ⌘ ⌥ ⌃ — a bare key would
    /// steal ordinary typing from every app.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
        var carbon: UInt32 = 0
        var symbols = ""
        if flags.contains(.control) { carbon |= UInt32(controlKey); symbols += "⌃" }
        if flags.contains(.option) { carbon |= UInt32(optionKey); symbols += "⌥" }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey); symbols += "⇧" }
        if flags.contains(.command) { carbon |= UInt32(cmdKey); symbols += "⌘" }
        keyCode = UInt32(event.keyCode)
        modifiers = carbon
        display = symbols + Self.name(for: event)
    }

    /// Builds one from a key code and Carbon modifiers (ShortcutsLens's Change Shortcut), named
    /// the way a key press would be in the current keyboard layout. Nil without ⌘ ⌥ or ⌃.
    init?(keyCode: Int, carbonModifiers: Int) {
        let mods = UInt32(carbonModifiers) & UInt32(controlKey | optionKey | shiftKey | cmdKey)
        guard mods & UInt32(controlKey | optionKey | cmdKey) != 0, (0...127).contains(keyCode) else { return nil }
        var symbols = ""
        if mods & UInt32(controlKey) != 0 { symbols += "⌃" }
        if mods & UInt32(optionKey) != 0 { symbols += "⌥" }
        if mods & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if mods & UInt32(cmdKey) != 0 { symbols += "⌘" }
        self.keyCode = UInt32(keyCode)
        modifiers = mods
        display = symbols + Self.name(keyCode: keyCode, characters: Self.layoutCharacter(keyCode))
    }

    private static func name(for event: NSEvent) -> String {
        name(keyCode: Int(event.keyCode), characters: event.charactersIgnoringModifiers)
    }

    private static func name(keyCode code: Int, characters: String?) -> String {
        if let f = fKeys[code] { return "F\(f)" }
        switch code {
        case kVK_Return: return "↩"
        case kVK_Space: return "Space"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default: return (characters ?? "?").uppercased()
        }
    }

    /// What the key types with no modifiers in the current layout ("g" for kVK_ANSI_G on QWERTY).
    private static func layoutCharacter(_ keyCode: Int) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> String? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var dead: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                        OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, chars.count, &length, &chars)
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length)
        }
    }

    /// Key code → F-key number. A table, not a range: the codes are scattered (F1 is 122,
    /// F20 is 90), and `kVK_F1...kVK_F20` trapped on the first key pressed.
    private static let fKeys: [Int: Int] = {
        let codes = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                     kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        return Dictionary(uniqueKeysWithValues: codes.enumerated().map { ($1, $0 + 1) })
    }()
}

/// System-wide shortcuts through Carbon's RegisterEventHotKey: works from a menu bar app
/// and needs no extra permission, unlike an event tap.
///
/// Shortcuts are named by string ids ("grid", "undo", "zone.left-half"), so new actions need
/// no change here: list them in `ShortcutCatalog` and handle the id in `perform`.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    var perform: ((String) -> Void)?
    private var refs: [UInt32: (ref: EventHotKeyRef, id: String)] = [:]
    private var installed = false

    /// Registers whatever is set in AppSettings, replacing earlier registrations.
    func apply() {
        installHandlerOnce()
        unregisterAll()
        var number: UInt32 = 1
        for item in ShortcutCatalog.all {
            guard let key = AppSettings.shared.shortcut(item.id) else { continue }
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x474C_4B48), id: number) // "GLKH"
            let status = RegisterEventHotKey(key.keyCode, key.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs[number] = (ref, item.id)
            } else {
                Diagnostics.note("hotkey \(key.display) for \(item.id) not registered (\(status)) — probably taken by another app")
            }
            number += 1
        }
        ShortcutsLensReport.publish()
    }

    /// For ShortcutsLens: the shortcuts that registered, named as Settings names them.
    var reportedShortcuts: [ShortcutsLensReport.Shortcut] {
        let registered = Set(refs.values.map(\.id))
        return ShortcutCatalog.all.compactMap { item in
            guard registered.contains(item.id), let key = AppSettings.shared.shortcut(item.id) else { return nil }
            return .init(id: item.id, title: item.title, keyCode: Int(key.keyCode), carbonModifiers: Int(key.modifiers),
                         category: item.category)
        }
    }

    /// ShortcutsLens's Change Shortcut: saves the keys as the Settings recorder does (so Settings
    /// shows them and sync carries them) and registers again. Nil when done, or why not.
    func change(id: String, keyCode: Int, carbonModifiers: Int) -> String? {
        guard let item = ShortcutCatalog.item(id) else { return "GridLock has no shortcut called \(id)." }
        guard let key = HotKey(keyCode: keyCode, carbonModifiers: carbonModifiers) else {
            return "GridLock shortcuts need ⌘, ⌥ or ⌃."
        }
        if let owner = ShortcutsSettings.clashingAction(key, for: item.id) {
            return "GridLock already uses \(key.display) for \(owner.title)."
        }
        let previous = AppSettings.shared.shortcut(item.id)
        AppSettings.shared.setShortcut(item.id, key)
        apply()
        guard !refs.values.contains(where: { $0.id == item.id }) else { return nil }
        // Taken by another app: keep the old keys rather than leave the shortcut dead.
        AppSettings.shared.setShortcut(item.id, previous)
        apply()
        return "\(key.display) is taken by another app, so GridLock kept \(previous?.display ?? "no shortcut")."
    }

    /// While a shortcut is being recorded, the current ones must not fire.
    func unregisterAll() {
        for entry in refs.values { UnregisterEventHotKey(entry.ref) }
        refs.removeAll()
    }

    private func installHandlerOnce() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &spec, nil, nil)
    }

    fileprivate func fire(_ number: UInt32) {
        guard let id = refs[number]?.id else { return }
        Diagnostics.note("hotkey: \(id)")
        perform?(id)
    }
}

/// Every action a global shortcut can run, in the order Settings lists them.
enum ShortcutCatalog {
    struct Item {
        let id: String
        let title: String
        let category: String
        let defaultKey: HotKey?
    }

    static var all: [Item] {
        [
            Item(id: "grid", title: "Show Grid", category: "Grid", defaultKey: controlOption(kVK_ANSI_G, "G")),
            Item(id: "undo", title: "Undo Move", category: "Grid", defaultKey: controlOption(kVK_ANSI_Z, "Z")),
            Item(id: "palette", title: "Open Palette", category: "Palette", defaultKey: controlOption(kVK_ANSI_P, "P")),
        ]
        + zones.map { name, title, key in Item(id: "zone." + name, title: title, category: "Zones", defaultKey: key) }
        + [
            Item(id: "display.next", title: "Next Display", category: "Displays",
                 defaultKey: HotKey(keyCode: UInt32(kVK_RightArrow), modifiers: UInt32(controlKey | optionKey | cmdKey), display: "⌃⌥⌘→")),
            Item(id: "display.previous", title: "Previous Display", category: "Displays",
                 defaultKey: HotKey(keyCode: UInt32(kVK_LeftArrow), modifiers: UInt32(controlKey | optionKey | cmdKey), display: "⌃⌥⌘←")),
        ]
    }

    /// Every zone in `Actions.namedZones`, in the order Settings lists them, with its default.
    private static let zones: [(String, String, HotKey?)] = [
        ("left-half", "Left Half", controlOption(kVK_LeftArrow, "←")),
        ("right-half", "Right Half", controlOption(kVK_RightArrow, "→")),
        ("top-half", "Top Half", nil),
        ("bottom-half", "Bottom Half", nil),
        ("left-third", "Left Third", nil),
        ("center-third", "Center Third", nil),
        ("right-third", "Right Third", nil),
        ("left-two-thirds", "Left Two-Thirds", nil),
        ("right-two-thirds", "Right Two-Thirds", nil),
        ("top-left", "Top Left Quarter", nil),
        ("top-right", "Top Right Quarter", nil),
        ("bottom-left", "Bottom Left Quarter", nil),
        ("bottom-right", "Bottom Right Quarter", nil),
        ("maximize", "Maximize", controlOption(kVK_UpArrow, "↑")),
        ("center", "Center", controlOption(kVK_ANSI_C, "C")),
    ]

    private static func controlOption(_ code: Int, _ key: String) -> HotKey {
        HotKey(keyCode: UInt32(code), modifiers: UInt32(controlKey | optionKey), display: "⌃⌥" + key)
    }

    static func item(_ id: String) -> Item? { all.first { $0.id == id } }
}

private func hotKeyHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ data: UnsafeMutableRawPointer?) -> OSStatus {
    var id = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                   nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
    guard status == noErr else { return status }
    let value = id.id
    // Carbon delivers hot keys on the main thread's event loop.
    MainActor.assumeIsolated { HotKeyCenter.shared.fire(value) }
    return noErr
}

/// Click, then press a shortcut. Esc cancels, Delete clears.
struct ShortcutRecorder: NSViewRepresentable {
    @Binding var hotKey: HotKey?

    func makeNSView(context: Context) -> RecorderButton {
        let view = RecorderButton()
        view.onChange = { hotKey = $0 }
        view.hotKey = hotKey
        return view
    }

    func updateNSView(_ view: RecorderButton, context: Context) {
        view.onChange = { hotKey = $0 }
        view.hotKey = hotKey
    }

    final class RecorderButton: NSButton {
        var onChange: ((HotKey?) -> Void)?
        var hotKey: HotKey? { didSet { refresh() } }
        private var recording = false { didSet { refresh() } }
        private var monitor: Any?

        override init(frame: NSRect) {
            super.init(frame: frame)
            bezelStyle = .rounded
            controlSize = .small
            target = self
            action = #selector(toggle)
            refresh()
        }

        required init?(coder: NSCoder) { fatalError() }

        override var intrinsicContentSize: NSSize { NSSize(width: 150, height: super.intrinsicContentSize.height) }

        private func refresh() {
            title = recording ? "Press a shortcut…" : (hotKey?.display ?? "Click to set")
        }

        @objc private func toggle() {
            recording ? stop() : start()
        }

        private func start() {
            recording = true
            HotKeyCenter.shared.unregisterAll()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                switch Int(event.keyCode) {
                case kVK_Escape:
                    self.stop()
                case kVK_Delete, kVK_ForwardDelete:
                    self.hotKey = nil
                    self.onChange?(nil)
                    self.stop()
                default:
                    guard let key = HotKey(event: event) else { NSSound.beep(); return nil }
                    self.hotKey = key
                    self.onChange?(key)
                    self.stop()
                }
                return nil
            }
        }

        private func stop() {
            recording = false
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            HotKeyCenter.shared.apply()
        }
    }
}
