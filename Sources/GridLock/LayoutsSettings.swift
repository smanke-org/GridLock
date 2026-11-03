import GridLockKit
import SwiftUI

/// Custom layouts: the list, and the layout editor in a sheet (S-025). A custom layout joins
/// a palette from the Palette pane's Available list.
struct LayoutsSettings: View {
    let desks: DeskTracker
    @Bindable private var selection = DeskSelection.shared
    @State private var selected: UUID?
    @State private var confirmingDelete: CustomLayout?

    private var layouts: [CustomLayout] { desks.store.library.customLayouts }
    private var selectedLayout: CustomLayout? { layouts.first { $0.id == selected } }

    var body: some View {
        Form {
            Section("Custom Layouts") {
                if layouts.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "rectangle.split.3x1").font(.largeTitle).foregroundStyle(.secondary)
                        Text("No Custom Layouts").font(.headline)
                        Caption("Draw a layout of your own, then add it to any palette.")
                        Button("New Layout…", action: newLayout)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                } else {
                    List(selection: $selected) {
                        ForEach(layouts) { layout in
                            LayoutRow(layout: layout, paletteCount: desks.store.library.paletteCount(using: layout.id))
                                .tag(layout.id)
                        }
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                    .frame(height: min(CGFloat(layouts.count) * 52 + 8, 270))
                    .contextMenu(forSelectionType: UUID.self) { ids in
                        if let layout = layouts.first(where: { $0.id == ids.first }) {
                            Button("Edit…") { edit(layout) }
                            Button("Duplicate") { duplicate(layout) }
                            Divider()
                            Button("Delete…") { confirmingDelete = layout }
                        }
                    } primaryAction: { ids in
                        if let layout = layouts.first(where: { $0.id == ids.first }) { edit(layout) }
                    }
                    .onDeleteCommand { confirmingDelete = selectedLayout }
                    HStack {
                        Button("New Layout…", action: newLayout).help("Draw a new custom layout")
                        Button("Edit…") { selectedLayout.map(edit) }
                            .disabled(selectedLayout == nil).help("Change the selected layout's name and zones")
                        Button("Duplicate") { selectedLayout.map(duplicate) }
                            .disabled(selectedLayout == nil).help("Make a copy of the selected layout to change")
                        Button("Delete…") { confirmingDelete = selectedLayout }
                            .disabled(selectedLayout == nil).help("Delete the selected layout and take it out of every palette")
                        Spacer()
                    }
                }
                Caption("Zones are kept as fractions of the display, so one layout fits every display shape. Add a custom layout to a palette in the Palette pane.")
            }
        }
        .formStyle(.grouped)
        .sheet(item: $selection.editingLayout) { layout in
            LayoutEditor(layout: layout, isNew: !layouts.contains { $0.id == layout.id },
                         selectedZone: selection.editingZone) { saved in
                desks.store.saveCustomLayout(saved)
                selected = saved.id
            }
        }
        .confirmationDialog("Delete “\(confirmingDelete?.name ?? "")”?", isPresented: Binding(
            get: { confirmingDelete != nil }, set: { if !$0 { confirmingDelete = nil } }), presenting: confirmingDelete) { layout in
            Button("Delete", role: .destructive) {
                desks.store.deleteCustomLayout(layout.id)
                if selected == layout.id { selected = nil }
            }
            Button("Cancel", role: .cancel) {}
        } message: { layout in
            let count = desks.store.library.paletteCount(using: layout.id)
            Text(count == 0 ? "This can't be undone."
                 : "It's also taken out of \(count) \(count == 1 ? "palette" : "palettes"). This can't be undone.")
        }
    }

    private func newLayout() {
        selection.editingZone = nil
        selection.editingLayout = CustomLayout(name: "", zones: [])
    }

    private func edit(_ layout: CustomLayout) {
        selection.editingZone = nil
        selection.editingLayout = layout
    }

    private func duplicate(_ layout: CustomLayout) {
        let copy = CustomLayout(name: "\(layout.name) Copy", zones: layout.zones)
        desks.store.saveCustomLayout(copy)
        selected = copy.id
    }
}

private struct LayoutRow: View {
    let layout: CustomLayout
    let paletteCount: Int

    var body: some View {
        HStack(spacing: 10) {
            LayoutThumbnail(kind: .custom(id: layout.id), customLayouts: [layout]).frame(width: 64, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(layout.name).lineLimit(1).truncationMode(.middle).help(layout.name)
                Text(details).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var details: String {
        let zones = layout.zones.count == 1 ? "1 zone" : "\(layout.zones.count) zones"
        switch paletteCount {
        case 0: return "\(zones) · in no palette yet"
        case 1: return "\(zones) · in 1 palette"
        default: return "\(zones) · in \(paletteCount) palettes"
        }
    }
}
