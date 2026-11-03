import AppKit
import GridLockKit
import SwiftUI

/// The layout editor sheet (S-025): a canvas with a snapping grid. Drag on empty space (or
/// on a zone that isn't selected) to draw a zone; drag the selected zone to move it, or its
/// edges to resize it; Delete removes it. Option turns snapping off. Zones under 5% of
/// either side are refused with a note.
struct LayoutEditor: View {
    @State private var layout: CustomLayout
    let isNew: Bool
    @State private var selectedZone: Int?
    let save: (CustomLayout) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var refused = false

    init(layout: CustomLayout, isNew: Bool, selectedZone: Int? = nil, save: @escaping (CustomLayout) -> Void) {
        _layout = State(initialValue: layout)
        self.isNew = isNew
        _selectedZone = State(initialValue: selectedZone.flatMap { layout.zones.indices.contains($0) ? $0 : nil })
        self.save = save
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "New Layout" : "Edit Layout").font(.headline)
            LabeledContent("Name") {
                TextField("Name", text: $layout.name, prompt: Text("Layout Name"))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
            }
            LayoutCanvasView(zones: $layout.zones, selected: $selectedZone, refused: $refused)
                .frame(width: 520, height: 325)
            if refused {
                Label("Zones must be at least 5% of the display's width and height.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            } else {
                Caption("Drag to draw a zone. Drag the selected zone to move it, or its edges to resize it. Hold Option to draw without snapping.")
            }
            HStack {
                Button("Add Zone", action: addZone).help("Add a zone in the middle of the layout")
                Button("Delete Zone", action: deleteZone).disabled(selectedZone == nil).help("Delete the selected zone (Delete)")
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isNew ? "Add Layout" : "Save") {
                    layout.name = layout.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    save(layout)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!layout.isValid)
                .help(layout.isValid ? "" : "Give the layout a name and at least one zone")
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private func addZone() {
        layout.zones.append(UnitRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        selectedZone = layout.zones.count - 1
        refused = false
    }

    private func deleteZone() {
        guard let i = selectedZone, layout.zones.indices.contains(i) else { return }
        layout.zones.remove(at: i)
        selectedZone = nil
    }
}

/// The canvas: grid lines, zones numbered in order, the selected zone's edge handles.
private struct LayoutCanvasView: View {
    @Binding var zones: [UnitRect]
    @Binding var selected: Int?
    @Binding var refused: Bool

    /// The zone being drawn, or nil once it's too small to keep.
    @State private var draft: UnitRect?
    @State private var drawing = false
    /// The zone as it was when a move or resize began.
    @State private var original: UnitRect?
    @FocusState private var focused: Bool

    private static let space = "layoutCanvas"

    private var divisions: Int? {
        NSEvent.modifierFlags.contains(.option) ? nil : LayoutCanvas.divisions
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.background.secondary)
                SnapGrid(divisions: LayoutCanvas.divisions).stroke(.secondary.opacity(0.22), lineWidth: 0.5)
                RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.secondary.opacity(0.6), lineWidth: 1)
                    .contentShape(Rectangle())
                    .gesture(drawGesture(size))
                ForEach(zones.indices, id: \.self) { i in
                    zoneView(i, size: size)
                }
                if let draft {
                    Rectangle()
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                        .frame(width: draft.width * size.width, height: draft.height * size.height)
                        .offset(x: draft.x * size.width, y: draft.y * size.height)
                        .allowsHitTesting(false)
                }
                if zones.isEmpty && !drawing {
                    Text("Drag to draw a zone").foregroundStyle(.secondary)
                        .frame(width: size.width, height: size.height)
                        .allowsHitTesting(false)
                }
            }
            .coordinateSpace(.named(Self.space))
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(focused ? 0.5 : 0), lineWidth: 3))
        .onKeyPress(keys: [.delete, .deleteForward]) { _ in
            guard let i = selected, zones.indices.contains(i) else { return .ignored }
            zones.remove(at: i)
            selected = nil
            return .handled
        }
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            nudge(press.key, resize: press.modifiers.contains(.shift))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Layout canvas")
    }

    @ViewBuilder
    private func zoneView(_ i: Int, size: CGSize) -> some View {
        let zone = zones[i]
        let isSelected = i == selected
        let rect = CGRect(x: zone.x * size.width, y: zone.y * size.height, width: zone.width * size.width, height: zone.height * size.height)
        ZStack {
            Rectangle().fill(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.3)) : AnyShapeStyle(.tertiary.opacity(0.8)))
            Rectangle().strokeBorder(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary), lineWidth: isSelected ? 2 : 1)
            Text("\(i + 1)").font(.title3.weight(.semibold)).foregroundStyle(isSelected ? .primary : .secondary)
        }
        .frame(width: rect.width, height: rect.height)
        .contentShape(Rectangle())
        .gesture(isSelected ? AnyGesture(adjustGesture(i, .body, size).map { _ in () })
                            : AnyGesture(drawGesture(size).map { _ in () }))
        .simultaneousGesture(TapGesture().onEnded { select(i) })
        .overlay { if isSelected { handles(i, size: rect.size, canvas: size) } }
        .offset(x: rect.minX, y: rect.minY)
        .accessibilityElement()
        .accessibilityLabel("Zone \(i + 1)")
        .accessibilityValue(Self.describe(zone))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { select(i) }
    }

    /// Thin strips along the selected zone's edges that resize it.
    private func handles(_ i: Int, size: CGSize, canvas: CGSize) -> some View {
        let t: CGFloat = 8
        return ZStack(alignment: .topLeading) {
            handle(i, .left, canvas).frame(width: t, height: size.height).offset(x: -t / 2)
                .pointerStyle(.frameResize(position: .leading))
            handle(i, .right, canvas).frame(width: t, height: size.height).offset(x: size.width - t / 2)
                .pointerStyle(.frameResize(position: .trailing))
            handle(i, .top, canvas).frame(width: size.width, height: t).offset(y: -t / 2)
                .pointerStyle(.frameResize(position: .top))
            handle(i, .bottom, canvas).frame(width: size.width, height: t).offset(y: size.height - t / 2)
                .pointerStyle(.frameResize(position: .bottom))
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// A clear strip with a small knob in the middle, so the edge reads as draggable.
    private func handle(_ i: Int, _ edge: LayoutCanvas.Handle, _ canvas: CGSize) -> some View {
        let vertical = edge == .left || edge == .right
        return ZStack {
            Rectangle().fill(Color.clear)
            Capsule().fill(Color.accentColor)
                .overlay(Capsule().strokeBorder(.background, lineWidth: 1))
                .frame(width: vertical ? 6 : 22, height: vertical ? 22 : 6)
        }
        .contentShape(Rectangle())
        .gesture(adjustGesture(i, edge, canvas))
    }

    private func drawGesture(_ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.space))
            .onChanged { value in
                focused = true
                drawing = true
                draft = LayoutCanvas.zone(from: unit(value.startLocation, size), to: unit(value.location, size), divisions: divisions)
            }
            .onEnded { value in
                drawing = false
                draft = nil
                if let zone = LayoutCanvas.zone(from: unit(value.startLocation, size), to: unit(value.location, size), divisions: divisions) {
                    zones.append(zone)
                    selected = zones.count - 1
                    refused = false
                } else {
                    refused = true
                }
            }
    }

    private func adjustGesture(_ i: Int, _ handle: LayoutCanvas.Handle, _ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
            .onChanged { value in
                guard zones.indices.contains(i) else { return }
                focused = true
                if original == nil { original = zones[i] }
                if let adjusted = LayoutCanvas.adjusted(original!, handle, dx: value.translation.width / size.width,
                                                        dy: value.translation.height / size.height, divisions: divisions) {
                    zones[i] = adjusted
                    refused = false
                } else {
                    refused = true
                }
            }
            .onEnded { _ in original = nil }
    }

    private func select(_ i: Int) {
        selected = i
        focused = true
    }

    /// Arrows move the selected zone one grid step; Shift-arrows move its right or bottom edge.
    private func nudge(_ key: KeyEquivalent, resize: Bool) -> KeyPress.Result {
        guard let i = selected, zones.indices.contains(i) else { return .ignored }
        let step = 1 / Double(LayoutCanvas.divisions)
        let (dx, dy): (Double, Double) = switch key {
        case .leftArrow: (-step, 0)
        case .rightArrow: (step, 0)
        case .upArrow: (0, -step)
        default: (0, step)
        }
        let handle: LayoutCanvas.Handle = resize ? (dx != 0 ? .right : .bottom) : .body
        if let adjusted = LayoutCanvas.adjusted(zones[i], handle, dx: dx, dy: dy) {
            zones[i] = adjusted
            refused = false
        } else {
            refused = true
        }
        return .handled
    }

    private func unit(_ p: CGPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: p.x / max(size.width, 1), y: p.y / max(size.height, 1))
    }

    /// "left 0%, top 0%, 25% wide, 100% tall", for VoiceOver.
    static func describe(_ z: UnitRect) -> String {
        func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }
        return "left \(pct(z.x)), top \(pct(z.y)), \(pct(z.width)) wide, \(pct(z.height)) tall"
    }
}

/// The snapping grid's lines.
private struct SnapGrid: Shape {
    let divisions: Int

    func path(in rect: CGRect) -> Path {
        var p = Path()
        for i in 1..<divisions {
            let x = rect.minX + rect.width * CGFloat(i) / CGFloat(divisions)
            let y = rect.minY + rect.height * CGFloat(i) / CGFloat(divisions)
            p.move(to: CGPoint(x: x, y: rect.minY))
            p.addLine(to: CGPoint(x: x, y: rect.maxY))
            p.move(to: CGPoint(x: rect.minX, y: y))
            p.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return p
    }
}
