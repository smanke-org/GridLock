import GridLockKit
import SwiftUI

/// Which layouts a display's palette shows, in what order, and their counts (S-020, S-021),
/// for any display at any desk — desks that aren't connected stay editable.
struct PaletteSettings: View {
    let desks: DeskTracker
    @Bindable private var selection = DeskSelection.shared

    var body: some View {
        Form {
            if let desk = selection.desk(in: desks), let display = selection.display(of: desk) {
                let isConnected = desk.id == desks.currentDeskID
                Section {
                    Picker("Desk", selection: Binding(get: { desk.id }, set: { selection.select(desk: $0) })) {
                        ForEach(desks.store.library.listed(current: desks.currentDeskID)) { d in
                            Text(d.id == desks.currentDeskID ? d.name : "\(d.name) (Not connected)").tag(d.id)
                        }
                    }
                    Picker("Display", selection: Binding(get: { display.key }, set: { selection.select(desk: desk.id, display: $0) })) {
                        ForEach(DeskSelection.ordered(desk.displays), id: \.key) { Text($0.title).tag($0.key) }
                    }
                    if !isConnected {
                        Label("Not connected. Changes apply when you're back at this desk.", systemImage: "powerplug")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Caption("Each display keeps its own palette at each desk. Drag layouts into the palette and drag to reorder them, or use the + and − buttons.")
                }
                // Named here too, since the pickers scroll out of sight above the lists.
                Section("\(display.title) Palette") {
                    PaletteEditor(desks: desks, desk: desk, display: display)
                }
                Section("Preview") {
                    PalettePreview(entries: palette(desk, display), customLayouts: desks.store.library.customLayouts,
                                   aspect: display.bounds.width / max(display.bounds.height, 1))
                }
            } else {
                Text("Recognizing your displays…").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func palette(_ desk: Desk, _ display: DisplayRecord) -> [PaletteEntry] {
        (desk.settings[display.key] ?? .suggested(for: display.bounds.cgRect.size)).palette
    }
}

/// What a row in either list carries when dragged: a family or custom layout to add, or a
/// palette entry to move or take out.
private enum DragItem {
    static func family(_ f: LayoutFamily) -> String { "family:\(f.rawValue)" }
    static func custom(_ id: UUID) -> String { "custom:\(id.uuidString)" }
    static func entry(_ id: UUID) -> String { "entry:\(id.uuidString)" }

    static func parse(_ s: String) -> (kind: String, value: String)? {
        let parts = s.split(separator: ":", maxSplits: 1).map(String.init)
        return parts.count == 2 ? (parts[0], parts[1]) : nil
    }
}

/// The two lists side by side: Available on the left, In Palette on the right.
private struct PaletteEditor: View {
    let desks: DeskTracker
    let desk: Desk
    let display: DisplayRecord

    private var customLayouts: [CustomLayout] { desks.store.library.customLayouts }
    private var entries: [PaletteEntry] {
        (desk.settings[display.key] ?? .suggested(for: display.bounds.cgRect.size)).palette
    }

    private func change(_ edit: (inout [PaletteEntry]) -> Void) {
        desks.store.update(desk: desk.id, display: display.key) { edit(&$0.palette) }
    }

    /// Adds a family or custom layout (from a + button or a drop) at `index`, or the end.
    private func add(_ item: String, at index: Int? = nil) {
        guard let (kind, value) = DragItem.parse(item) else { return }
        change { palette in
            switch kind {
            case "family":
                guard let family = LayoutFamily(rawValue: value) else { return }
                palette.insert(PaletteEntry(kind: Palette.adding(family, to: palette)), at: min(index ?? palette.count, palette.count))
            case "custom":
                guard let id = UUID(uuidString: value) else { return }
                palette.insert(PaletteEntry(kind: .custom(id: id)), at: min(index ?? palette.count, palette.count))
            case "entry":
                // A palette row dropped back into the palette: moved there.
                guard let id = UUID(uuidString: value), let from = palette.firstIndex(where: { $0.id.uuidString == id.uuidString })
                else { return }
                palette = Palette.moving(palette, from: [from], to: index ?? palette.count)
            default: break
            }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Available").font(.subheadline.weight(.semibold))
                List {
                    ForEach(LayoutFamily.allCases, id: \.self) { family in
                        AvailableRow(kind: family.starter, title: family.title, customLayouts: customLayouts) {
                            add(DragItem.family(family))
                        }
                        .draggable(DragItem.family(family))
                    }
                    if !customLayouts.isEmpty {
                        Section("Custom Layouts") {
                            ForEach(customLayouts) { layout in
                                AvailableRow(kind: .custom(id: layout.id), title: layout.name, customLayouts: customLayouts) {
                                    add(DragItem.custom(layout.id))
                                }
                                .draggable(DragItem.custom(layout.id))
                            }
                        }
                    }
                }
                .listStyle(.bordered)
                .alternatingRowBackgrounds()
                // A palette row dragged back here leaves the palette.
                .dropDestination(for: String.self) { items, _ in
                    let ids = Set(items.compactMap { DragItem.parse($0) }.filter { $0.kind == "entry" }.map(\.value))
                    guard !ids.isEmpty else { return false }
                    change { $0.removeAll { ids.contains($0.id.uuidString) } }
                    return true
                }
            }
            .frame(width: 200)

            VStack(alignment: .leading, spacing: 6) {
                Text("In Palette").font(.subheadline.weight(.semibold))
                List {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        PaletteRow(entry: entry, customLayouts: customLayouts, isFirst: index == 0, isLast: index == entries.count - 1,
                                   setKind: { kind in change { p in
                                       if let i = p.firstIndex(where: { $0.id == entry.id }) { p[i].kind = kind }
                                   } },
                                   move: { delta in change { p in
                                       p = Palette.moving(p, from: [index], to: delta < 0 ? index - 1 : index + 2)
                                   } },
                                   remove: { change { $0.removeAll { $0.id == entry.id } } })
                        .draggable(DragItem.entry(entry.id))
                    }
                    .onMove { from, to in change { $0 = Palette.moving($0, from: from, to: to) } }
                    .dropDestination(for: String.self) { items, index in
                        for item in items.reversed() { add(item, at: index) }
                    }
                }
                .listStyle(.bordered)
                .alternatingRowBackgrounds()
                .overlay {
                    if entries.isEmpty {
                        VStack(spacing: 4) {
                            Text("This palette is empty").foregroundStyle(.secondary)
                            Caption("Add layouts from Available.")
                        }
                    }
                }
            }
        }
        .frame(height: 330)
    }
}

private struct AvailableRow: View {
    let kind: LayoutKind
    let title: String
    let customLayouts: [CustomLayout]
    let add: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            LayoutThumbnail(kind: kind, customLayouts: customLayouts).frame(width: 36, height: 23)
            Text(title).lineLimit(1).truncationMode(.middle).help(title)
            Spacer(minLength: 4)
            Button(action: add) { Image(systemName: "plus.circle") }
                .buttonStyle(.borderless)
                .help("Add \(title) to the palette")
                .accessibilityLabel("Add \(title)")
        }
        .contextMenu { Button("Add to Palette", action: add) }
    }
}

/// One palette entry: its thumbnail, its name (which follows the count) and the count.
private struct PaletteRow: View {
    let entry: PaletteEntry
    let customLayouts: [CustomLayout]
    let isFirst: Bool
    let isLast: Bool
    let setKind: (LayoutKind) -> Void
    let move: (Int) -> Void
    let remove: () -> Void

    private var title: String { entry.kind.title(custom: customLayouts) }

    var body: some View {
        HStack(spacing: 8) {
            LayoutThumbnail(kind: entry.kind, customLayouts: customLayouts).frame(width: 36, height: 23)
            Text(title).lineLimit(1).truncationMode(.middle).help(title)
            Spacer(minLength: 4)
            CountControl(kind: entry.kind, set: setKind)
            Button(action: remove) { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .help("Remove \(title) from the palette")
                .accessibilityLabel("Remove \(title)")
        }
        .contextMenu {
            Button("Move Up") { move(-1) }.disabled(isFirst)
            Button("Move Down") { move(1) }.disabled(isLast)
            Divider()
            Button("Remove from Palette", action: remove)
        }
        .accessibilityAction(named: "Move Up") { if !isFirst { move(-1) } }
        .accessibilityAction(named: "Move Down") { if !isLast { move(1) } }
    }
}

/// The count for a family: a stepper for Columns and Rows, a pair for Grid, the side order
/// for the splits. Maximize, Center and custom layouts have none.
private struct CountControl: View {
    let kind: LayoutKind
    let set: (LayoutKind) -> Void

    var body: some View {
        switch kind {
        case let .columns(n):
            Stepper("Columns", value: Binding(get: { n }, set: { set(kind.withCount($0)) }), in: LayoutKind.columnCounts)
                .labelsHidden().help("Number of columns").accessibilityValue("\(n)")
        case let .rows(n):
            Stepper("Rows", value: Binding(get: { n }, set: { set(kind.withCount($0)) }), in: LayoutKind.rowCounts)
                .labelsHidden().help("Number of rows").accessibilityValue("\(n)")
        case let .grid(c, r):
            HStack(spacing: 2) {
                Text("\(c)").monospacedDigit().foregroundStyle(.secondary)
                Stepper("Columns", value: Binding(get: { c }, set: { set(kind.withGrid(columns: $0, rows: r)) }), in: LayoutKind.gridRange)
                    .labelsHidden().help("Number of columns").accessibilityValue("\(c)")
                Text("×").foregroundStyle(.secondary).padding(.horizontal, 2)
                Text("\(r)").monospacedDigit().foregroundStyle(.secondary)
                Stepper("Rows", value: Binding(get: { r }, set: { set(kind.withGrid(columns: c, rows: $0)) }), in: LayoutKind.gridRange)
                    .labelsHidden().help("Number of rows").accessibilityValue("\(r)")
            }
        case .split:
            Picker("Sides", selection: Binding(get: { kind }, set: set)) {
                // Short labels: the row's name already says it in words.
                ForEach(LayoutKind.splits, id: \.self) { split in
                    if case let .split(lead, parts) = split {
                        Text("\(fraction(lead, parts)) + \(fraction(parts - lead, parts))").tag(split)
                    }
                }
            }
            .labelsHidden().fixedSize().help("Which side is wider")
        default:
            EmptyView()
        }
    }

    private func fraction(_ n: Int, _ d: Int) -> String {
        ["1/3": "⅓", "2/3": "⅔", "1/4": "¼", "3/4": "¾"]["\(n)/\(d)"] ?? "\(n)/\(d)"
    }
}

/// The palette as it will drop down, thumbnails shaped like the display.
private struct PalettePreview: View {
    let entries: [PaletteEntry]
    let customLayouts: [CustomLayout]
    let aspect: CGFloat

    var body: some View {
        let width: CGFloat = aspect >= 1 ? 76 : 44
        let height = width / max(aspect, 0.3)
        if entries.isEmpty {
            Text("Nothing to show: the palette is empty.").foregroundStyle(.secondary)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: width + 8), spacing: 10, alignment: .top)], spacing: 12) {
                ForEach(entries) { entry in
                    VStack(spacing: 4) {
                        LayoutThumbnail(kind: entry.kind, customLayouts: customLayouts).frame(width: width, height: height)
                        Text(entry.kind.title(custom: customLayouts)).font(.caption2).lineLimit(2)
                            .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Palette preview")
        }
    }
}
