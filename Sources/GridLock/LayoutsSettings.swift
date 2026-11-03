import GridLockKit
import SwiftUI

/// Custom layouts and the layout editor. (S-025 — not built yet.)
struct LayoutsSettings: View {
    let desks: DeskTracker

    var body: some View {
        Form {
            Section {
                if desks.store.library.customLayouts.isEmpty {
                    Text("No custom layouts yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(desks.store.library.customLayouts) { Text($0.name) }
                }
            }
        }
        .formStyle(.grouped)
    }
}
