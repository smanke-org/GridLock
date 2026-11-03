import GridLockKit
import SwiftUI

/// A recorder for every shortcut in `ShortcutCatalog`, grouped as the catalog groups them.
/// A key another GridLock action already uses is refused, naming that action.
struct ShortcutsSettings: View {
    @AppStorage(SizeCycle.settingsKey) private var cycleOrder = SizeCycle.Order.halfTwoThirdsThird
    /// The refused key and why, under the row that tried it.
    @State private var clash: (id: String, message: String)?

    private static let categories = ["Grid", "Zones", "Displays"]

    var body: some View {
        Form {
            ForEach(Self.categories, id: \.self) { category in
                Section(category) {
                    ForEach(ShortcutCatalog.all.filter { $0.category == category }, id: \.id) { item in
                        row(item)
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
                Caption("Shortcuts work in every app. A shortcut another app already uses may not respond.")
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func row(_ item: ShortcutCatalog.Item) -> some View {
        LabeledContent(item.title) {
            ShortcutRecorder(hotKey: Binding(
                get: { AppSettings.shared.shortcut(item.id) },
                set: { set($0, for: item) }))
                .fixedSize()
        }
        if let clash, clash.id == item.id {
            Label(clash.message, systemImage: "exclamationmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func set(_ key: HotKey?, for item: ShortcutCatalog.Item) {
        if let key, let owner = Self.clashingAction(key, for: item.id) {
            clash = (item.id, "\(key.display) is already used by \(owner.title).")
        } else {
            clash = nil
            AppSettings.shared.setShortcut(item.id, key)
        }
    }

    /// The other action using this key, if any.
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
