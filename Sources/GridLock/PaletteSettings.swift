import GridLockKit
import SwiftUI

/// Which layouts each display's palette shows, in what order, and their counts.
/// (S-020, S-021 — read-only list until those stories are built.)
struct PaletteSettings: View {
    let desks: DeskTracker

    var body: some View {
        Form {
            ForEach(desks.live, id: \.key) { display in
                Section(display.isBuiltin ? "Built-in Display" : display.name) {
                    ForEach(desks.settings(for: display).palette) { entry in
                        Text(entry.kind.title(custom: desks.store.library.customLayouts))
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
