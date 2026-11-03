import SwiftUI

/// A recorder for every shortcut in `ShortcutCatalog`. (S-030 adds zone shortcuts and the
/// clash check.)
struct ShortcutsSettings: View {
    var body: some View {
        Form {
            Section {
                ForEach(ShortcutCatalog.all, id: \.id) { item in
                    LabeledContent(item.title) {
                        ShortcutRecorder(hotKey: Binding(
                            get: { AppSettings.shared.shortcut(item.id) },
                            set: { AppSettings.shared.setShortcut(item.id, $0) }))
                            .fixedSize()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
