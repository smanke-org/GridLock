import GridLockKit
import SwiftUI

/// The palette's undo target, drawn for its style (Settings › Palette): a window dropped on
/// it goes back to where it was before GridLock last moved it. `hot` while a window is over
/// it: filled and outlined with the accent color, so it reads without relying on color alone.
/// Styles with glass of their own (the bubble, the corner button) draw over it.
struct UndoTarget: View {
    let style: UndoTargetStyle
    let hot: Bool
    let app: String
    /// For the Preview Tile: where the window goes back to on its display.
    var preview: UnitRect?

    private static let tileRadius: CGFloat = 4.6

    private var tint: AnyShapeStyle { hot ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary) }
    private var hotFill: Color { Color.accentColor.opacity(0.28) }

    var body: some View {
        content
            .accessibilityElement()
            .accessibilityLabel("Undo Move")
            .accessibilityValue(app.isEmpty ? "" : "Puts \(app)'s window back")
    }

    @ViewBuilder
    private var content: some View {
        switch style {
        case .none:
            EmptyView()
        case .endTile, .dividedEndTile, .leadingTile, .hangingLip:
            tile { icon(18) }
        case .dropWell:
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hot ? AnyShapeStyle(hotFill) : AnyShapeStyle(.clear))
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(hot ? Color.accentColor : Color.primary.opacity(0.4),
                                  style: StrokeStyle(lineWidth: hot ? 2 : 1, dash: [4, 3]))
                icon(18)
            }
        case .previewTile:
            tile {
                GeometryReader { proxy in
                    let size = proxy.size
                    let inset = max(2, min(size.width, size.height) * 0.06) + 2
                    let area = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
                    let spot = preview ?? UnitRect(x: 0.2, y: 0.15, width: 0.5, height: 0.6)
                    let rect = CGRect(x: area.minX + spot.x * area.width, y: area.minY + spot.y * area.height,
                                      width: max(spot.width * area.width, 6), height: max(spot.height * area.height, 6))
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(hot ? AnyShapeStyle(Color.accentColor.opacity(0.35)) : AnyShapeStyle(.clear))
                            .strokeBorder(hot ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary.opacity(0.55)),
                                          style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                        icon(12)
                            .frame(width: size.width - 5, height: size.height - 4, alignment: .bottomTrailing)
                    }
                }
            }
        case .footerStrip:
            ZStack {
                Capsule().fill(hot ? AnyShapeStyle(hotFill) : AnyShapeStyle(.background.secondary))
                Capsule().strokeBorder(hot ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary.opacity(0.5)), lineWidth: hot ? 2 : 1)
                HStack(spacing: 6) {
                    icon(13)
                    Text(hot ? style.hotCaption(app: app) : style.caption ?? "")
                        .font(.caption)
                        .foregroundStyle(hot ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 12)
            }
        case .sideBubble, .cornerButton:
            ZStack {
                if hot {
                    Circle().fill(hotFill)
                    Circle().strokeBorder(Color.accentColor, lineWidth: 2)
                }
                icon(style == .sideBubble ? 20 : 15)
            }
            .padding(1.5)
        case .endCap:
            ZStack {
                if hot {
                    UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                           bottomTrailingRadius: PaletteLayout.radius - 1.5,
                                           topTrailingRadius: PaletteLayout.radius - 1.5, style: .continuous)
                        .fill(hotFill)
                        .padding(EdgeInsets(top: 1.5, leading: 0, bottom: 1.5, trailing: 1.5))
                }
                VStack(spacing: 4) {
                    icon(20)
                    Text(style.caption ?? "").font(.caption)
                        .foregroundStyle(hot ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
                }
            }
        }
    }

    private func icon(_ size: CGFloat) -> some View {
        Image(systemName: "arrow.uturn.backward")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(tint)
    }

    /// A tile shaped like the layouts beside it.
    private func tile(@ViewBuilder _ inside: () -> some View) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Self.tileRadius, style: .continuous)
                .fill(hot ? AnyShapeStyle(hotFill) : AnyShapeStyle(.background.secondary))
            RoundedRectangle(cornerRadius: Self.tileRadius, style: .continuous)
                .strokeBorder(hot ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary.opacity(0.5)), lineWidth: hot ? 2 : 1)
            inside()
        }
    }
}
