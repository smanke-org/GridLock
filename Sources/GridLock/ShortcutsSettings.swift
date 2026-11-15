import AppKit
import GridLockKit
import SwiftUI

/// A shortcut box for every shortcut in `ShortcutCatalog`, grouped as the catalog groups them.
/// Keys another GridLock action already uses move to the one being set; the editor says so first.
struct ShortcutsSettings: View {
    @AppStorage(SizeCycle.settingsKey) private var cycleOrder = SizeCycle.Order.halfTwoThirdsThird

    private static let categories = ["Grid", "Palette", "Zones", "Displays"]

    var body: some View {
        Form {
            ForEach(Self.categories, id: \.self) { category in
                Section(category) {
                    ForEach(ShortcutCatalog.all.filter { $0.category == category }, id: \.id) { item in
                        row(item)
                        if item.id == "palette" { dragKeys }
                        if category == "Zones", item.id == "zone.bottom-half" {
                            Picker("Pressed again", selection: $cycleOrder) {
                                ForEach(SizeCycle.Order.allCases, id: \.self) { Text($0.title).tag($0) }
                            }
                            Caption("Pressing a half's shortcut again within 2 seconds steps the same window through these sizes on that side.")
                        }
                    }
                }
            }
            Section {
                Caption("Click a shortcut to set it: pick the modifier keys and type a key, or press the shortcut. Keys another GridLock shortcut has are moved here. Shortcuts work in every app; one another app already uses may not respond.")
            }
        }
        .formStyle(.grouped)
    }

    /// The keys that, held while dragging a window, open the palette next to the pointer.
    @ViewBuilder
    private var dragKeys: some View {
        let settings = AppSettings.shared
        Toggle("Show the palette's tab while dragging", isOn: Binding(
            get: { settings.showsPaletteTab }, set: { settings.showsPaletteTab = $0 }))
        Caption("While you drag a window, the palette's bottom edge peeks down from under the menu bar at the top center of the display. Drag onto it and the palette slides down.")
        LabeledContent("Hold while dragging") {
            HStack(spacing: 4) {
                ForEach(AppSettings.dragModifierChoices, id: \.rawValue) { key in
                    Toggle(isOn: Binding(
                        get: { settings.paletteModifiers.contains(key) },
                        set: { on in
                            if on { settings.paletteModifiers.insert(key) } else { settings.paletteModifiers.remove(key) }
                        })) {
                        Text(Self.symbol(key)).frame(minWidth: 18)
                    }
                    .toggleStyle(.button)
                    .accessibilityLabel(Self.name(key))
                    .help("Hold \(Self.name(key)) while dragging a window to open the palette")
                }
            }
        }
        Caption(settings.paletteModifiers.isEmpty
                ? "Off: drag a window to the top edge of a display to open the palette."
                : "Hold \(Self.symbols(settings.paletteModifiers)) while dragging a window to open the palette right away, above the pointer, without going to the top edge. Let go of the keys to close it.")
        if settings.paletteModifiers == .control {
            Label("⌃ alone turns a click into a right-click: press it after you start dragging.", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private static func symbol(_ key: NSEvent.ModifierFlags) -> String {
        switch key {
        case .control: "⌃"
        case .option: "⌥"
        case .shift: "⇧"
        default: "⌘"
        }
    }

    private static func name(_ key: NSEvent.ModifierFlags) -> String {
        switch key {
        case .control: "Control"
        case .option: "Option"
        case .shift: "Shift"
        default: "Command"
        }
    }

    private static func symbols(_ keys: NSEvent.ModifierFlags) -> String {
        AppSettings.dragModifierChoices.filter(keys.contains).map(symbol).joined()
    }

    @ViewBuilder
    private func row(_ item: ShortcutCatalog.Item) -> some View {
        LabeledContent(item.title) {
            // The editor has already taken these keys off any other shortcut.
            ShortcutRecorder(hotKey: Binding(
                get: { AppSettings.shared.shortcut(item.id) },
                set: { AppSettings.shared.setShortcut(item.id, $0) }), id: item.id)
                .fixedSize()
        }
    }

    /// The other action using this key, if any (ShortcutsLens's Change Shortcut refuses it).
    static func clashingAction(_ key: HotKey, for id: String) -> ShortcutCatalog.Item? {
        func combo(_ k: HotKey) -> [UInt32] { [k.keyCode, k.modifiers] }
        let owner = ShortcutClash.owner(of: combo(key), for: id, among: ShortcutCatalog.all.map(\.id)) {
            AppSettings.shared.shortcut($0).map(combo)
        }
        return owner.flatMap(ShortcutCatalog.item)
    }
}

extension SizeCycle {
    /// Where Settings keeps the order (UserDefaults).
    static let settingsKey = "cycleOrder"

    @MainActor static var order: Order {
        UserDefaults.standard.string(forKey: settingsKey).flatMap(Order.init) ?? .halfTwoThirdsThird
    }
}
