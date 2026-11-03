import GridLockKit
import SwiftUI

/// Every desk GridLock knows (S-023), and the chosen desk as a picture of its displays with
/// an inspector for the selected display's grid (S-006). Right-click a display, or use the
/// inspector's menu, to copy, paste or reset its settings (S-024).
struct DesksSettings: View {
    let desks: DeskTracker
    @Bindable private var selection = DeskSelection.shared
    @State private var confirmingDelete: Desk?
    @State private var windowKeeperNames: [String: String] = [:]

    var body: some View {
        Form {
            if let desk = selection.desk(in: desks) {
                Section("Desks") {
                    DeskList(desks: desks, windowKeeperNames: windowKeeperNames, confirmingDelete: $confirmingDelete)
                }
                Section {
                    HStack(alignment: .top, spacing: 16) {
                        DeskPictureView(desks: desks, desk: desk)
                            .frame(minWidth: 280, maxWidth: .infinity, minHeight: 200, maxHeight: 200)
                        Divider()
                        if let display = selection.display(of: desk) {
                            DisplayInspector(desks: desks, desk: desk, display: display)
                                .frame(width: 200)
                        }
                    }
                    Caption("Each display keeps its own grid at each desk. Click a display to change its grid.")
                } header: {
                    Text(desk.caption).lineLimit(1).truncationMode(.middle)
                }
            } else {
                Text("Recognizing your displays…").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { windowKeeperNames = DeskTracker.windowKeeperNames() }
        .sheet(item: Binding(get: { desks.store.desk(id: selection.renaming) },
                             set: { selection.renaming = $0?.id })) { desk in
            RenameDeskSheet(desk: desk) { desks.store.rename(desk.id, to: $0) }
        }
        .confirmationDialog("Delete “\(confirmingDelete?.name ?? "")”?", isPresented: Binding(
            get: { confirmingDelete != nil }, set: { if !$0 { confirmingDelete = nil } }), presenting: confirmingDelete) { desk in
            Button("Delete", role: .destructive) {
                if selection.deskID == desk.id { selection.deskID = nil }
                desks.store.delete(desk.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("GridLock forgets this desk's grids and palettes. If you connect these displays again, they start as a new desk.")
        }
    }
}

// MARK: - Desk list

extension Desk {
    /// "Dell P4317Q + Built-in", left to right.
    var displayNames: String { DeskSignature.defaultName(for: DeskSelection.ordered(displays)) }

    /// "Desk: Office (Dell P4317Q + Built-in)", or just "Desk: Dell P4317Q + Built-in" for a
    /// desk still named after its displays.
    var caption: String { displayNames == name ? "Desk: \(name)" : "Desk: \(name) (\(displayNames))" }
}

private struct DeskList: View {
    let desks: DeskTracker
    let windowKeeperNames: [String: String]
    @Binding var confirmingDelete: Desk?
    @Bindable private var selection = DeskSelection.shared

    private var listed: [Desk] { desks.store.library.listed(current: desks.currentDeskID) }
    private var selectedID: UUID? { selection.desk(in: desks)?.id }

    var body: some View {
        List(selection: Binding(get: { selectedID }, set: { if let id = $0 { selection.select(desk: id) } })) {
            ForEach(listed) { desk in
                DeskRow(desk: desk, isCurrent: desk.id == desks.currentDeskID)
                    .tag(desk.id)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .frame(height: min(CGFloat(max(listed.count, 1)) * 44 + 8, 190))
        .contextMenu(forSelectionType: UUID.self) { ids in
            if let desk = desks.store.desk(id: ids.first) { menu(for: desk) }
        } primaryAction: { ids in
            if let id = ids.first { selection.renaming = id }
        }
        HStack {
            Button("Rename…") { selection.renaming = selectedID }
                .disabled(selectedID == nil)
                .help("Give the selected desk a new name")
            Button("Delete…") { confirmingDelete = desks.store.desk(id: selectedID) }
                .disabled(!canDelete(selectedID))
                .help(selectedID == desks.currentDeskID ? "You can't delete the desk you're at." : "Forget the selected desk and its settings")
            Spacer()
        }
    }

    private func canDelete(_ id: UUID?) -> Bool {
        id.map { desks.store.library.canDelete($0, current: desks.currentDeskID) } ?? false
    }

    @ViewBuilder private func menu(for desk: Desk) -> some View {
        Button("Rename…") { selection.renaming = desk.id }
        if let name = windowKeeperNames[desk.signature], name != desk.name {
            Button("Use WindowKeeper's Name, “\(name)”") { desks.store.rename(desk.id, to: name) }
        }
        Divider()
        Button("Delete…") { confirmingDelete = desk }.disabled(!canDelete(desk.id))
    }
}

private struct DeskRow: View {
    let desk: Desk
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: desk.displays.count > 1 ? "display.2" : (desk.displays.first?.isBuiltin == true ? "laptopcomputer" : "display"))
                .font(.title3).foregroundStyle(.secondary).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(desk.name).lineLimit(1).truncationMode(.middle).help(desk.name)
                    if isCurrent {
                        // Outlined, not filled: it stays readable on the selected row.
                        Text("Current").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .overlay(Capsule().strokeBorder(.secondary))
                    }
                }
                if desk.displayNames != desk.name {
                    Text(desk.displayNames).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer()
            if !isCurrent {
                Text("Last used \(desk.lastUsed, format: .relative(presentation: .named))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Desk picture

/// The desk's displays to scale, in their arrangement. The selected one shows its grid
/// lines (with the margin) and an accent outline.
private struct DeskPictureView: View {
    let desks: DeskTracker
    let desk: Desk
    @Bindable private var selection = DeskSelection.shared

    var body: some View {
        GeometryReader { proxy in
            let records = DeskSelection.ordered(desk.displays)
            let frames = DeskPicture.fit(records.map(\.bounds.cgRect), in: proxy.size, inset: 6)
            let selectedKey = selection.display(of: desk)?.key
            ZStack(alignment: .topLeading) {
                ForEach(Array(zip(records, frames)), id: \.0.key) { record, frame in
                    let settings = desk.settings[record.key] ?? .suggested(for: record.bounds.cgRect.size)
                    DisplayTile(record: record, grid: settings.grid, scale: frame.width / max(record.bounds.width, 1),
                                isSelected: record.key == selectedKey) {
                        selection.select(desk: desk.id, display: record.key)
                    }
                    .frame(width: frame.width - 4, height: frame.height - 4)
                    .offset(x: frame.minX + 2, y: frame.minY + 2)
                    .contextMenu { DisplaySettingsMenu(desks: desks, desk: desk, display: record) }
                }
            }
        }
    }
}

private struct DisplayTile: View {
    let record: DisplayRecord
    let grid: GridSpec
    let scale: CGFloat
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.12)) : AnyShapeStyle(.background.secondary))
                if isSelected {
                    GridLines(grid: grid, margin: grid.margin * scale)
                        .stroke(Color.accentColor.opacity(0.55), lineWidth: 1)
                        .padding(3)
                }
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary.opacity(0.6)),
                                  lineWidth: isSelected ? 2 : 1)
                VStack(spacing: 1) {
                    Text(record.isBuiltin ? "Built-in" : record.name).font(.caption.weight(.medium))
                        .lineLimit(1).truncationMode(.middle)
                    Text("\(grid.columns) × \(grid.rows)").font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(.background.opacity(0.75), in: RoundedRectangle(cornerRadius: 4))
                .padding(4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(record.title): \(grid.columns) × \(grid.rows) grid. Right-click to copy or paste its settings.")
        .accessibilityLabel("\(record.title), \(grid.columns) by \(grid.rows) grid")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A display's grid lines, inset by its margin (already scaled to the picture).
private struct GridLines: Shape {
    let grid: GridSpec
    let margin: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: min(margin, rect.width / 4), dy: min(margin, rect.height / 4))
        var p = Path()
        p.addRect(r)
        for c in 1..<max(grid.columns, 1) {
            let x = r.minX + r.width * CGFloat(c) / CGFloat(grid.columns)
            p.move(to: CGPoint(x: x, y: r.minY))
            p.addLine(to: CGPoint(x: x, y: r.maxY))
        }
        for row in 1..<max(grid.rows, 1) {
            let y = r.minY + r.height * CGFloat(row) / CGFloat(grid.rows)
            p.move(to: CGPoint(x: r.minX, y: y))
            p.addLine(to: CGPoint(x: r.maxX, y: y))
        }
        return p
    }
}

// MARK: - Inspector

private struct DisplayInspector: View {
    let desks: DeskTracker
    let desk: Desk
    let display: DisplayRecord

    private var grid: GridSpec { (desk.settings[display.key] ?? .suggested(for: display.bounds.cgRect.size)).grid }
    private var isConnected: Bool { desk.id == desks.currentDeskID }

    private func binding<T>(_ path: WritableKeyPath<GridSpec, T>) -> Binding<T> {
        Binding(get: { grid[keyPath: path] },
                set: { value in desks.store.update(desk: desk.id, display: display.key) { $0.grid[keyPath: path] = value } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(display.title).font(.headline).lineLimit(1).truncationMode(.middle).help(display.title)
                    Text("\(Int(display.bounds.width)) × \(Int(display.bounds.height))").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    DisplaySettingsMenu(desks: desks, desk: desk, display: display)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Copy this display's grid and palette, paste another display's, or reset to defaults")
                .accessibilityLabel("Display Settings")
            }
            if !isConnected {
                Label("Not connected", systemImage: "powerplug")
                    .font(.caption).foregroundStyle(.secondary)
                    .help("This desk isn't connected now. Its settings still change, and apply when you're back at it.")
            }
            Text("Grid").font(.subheadline.weight(.semibold)).padding(.top, 4)
            row("Columns", "\(grid.columns)") {
                Stepper("Columns", value: binding(\.columns), in: GridSpec.columnRange)
            }
            row("Rows", "\(grid.rows)") {
                Stepper("Rows", value: binding(\.rows), in: GridSpec.rowRange)
            }
            row("Gap", "\(Int(grid.gap)) pt") {
                Stepper("Gap", value: binding(\.gap), in: GridSpec.spacingRange, step: 2)
            }
            .help("Space between snapped windows")
            row("Margin", "\(Int(grid.margin)) pt") {
                Stepper("Margin", value: binding(\.margin), in: GridSpec.spacingRange, step: 2)
            }
            .help("Space between snapped windows and the display's edges")
        }
    }

    private func row(_ label: String, _ value: String, @ViewBuilder stepper: () -> some View) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(.secondary)
            stepper().labelsHidden().accessibilityValue(value)
        }
    }
}

/// Copy Settings, Paste Settings, Reset to Defaults: the display's right-click menu and the
/// inspector's menu.
private struct DisplaySettingsMenu: View {
    let desks: DeskTracker
    let desk: Desk
    let display: DisplayRecord
    @Bindable private var selection = DeskSelection.shared

    var body: some View {
        Button("Copy Settings") {
            selection.clipboard = desk.settings[display.key] ?? .suggested(for: display.bounds.cgRect.size)
        }
        Button("Paste Settings") {
            if let clip = selection.clipboard { desks.store.paste(clip, desk: desk.id, display: display.key) }
        }
        .disabled(selection.clipboard == nil)
        Divider()
        Button("Reset to Defaults") { desks.store.reset(desk: desk.id, display: display.key) }
    }
}

// MARK: - Rename

struct RenameDeskSheet: View {
    let desk: Desk
    let rename: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename Desk").font(.headline)
            TextField("Name", text: $name, prompt: Text(desk.name))
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
                .onSubmit(save)
            Caption("Displays: \(desk.displayNames)")
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Rename", action: save).keyboardShortcut(.defaultAction).disabled(trimmed.isEmpty)
            }
        }
        .padding(20)
        .onAppear { name = desk.name }
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        rename(trimmed)
        dismiss()
    }
}
