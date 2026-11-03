#if DEBUG
import AppKit
import GridLockKit
import SwiftUI

/// Fifteen looks for the palette, to choose one from (design/PALETTE-DESIGNS.md). Snapshot
/// mode only: pages `design-01` … `design-15`, drawn over the staged desktop with the right
/// third of Columns × 3 under the pointer. Each design reads only its own colors.
@MainActor
enum PaletteDesigns {
    static let names = ["Glass Tiles", "Neon", "Blueprint", "Index Cards", "Ring", "Shelf", "Strip", "Terminal",
                        "Brutalist", "Aurora", "Tiny Displays", "Fanned Deck", "HUD", "Swiss", "Isometric"]
    static var pages: [String] { names.indices.map { String(format: "design-%02d", $0 + 1) } }

    /// What every design shows: the suggested palette for a 6 × 4 grid, one zone lit.
    struct Scene {
        let kinds: [LayoutKind]
        let lit = (entry: 1, zone: 2)
        var titles: [String] { kinds.map { $0.title() } }
    }

    enum Placement {
        /// Centered under the pointer, just below the menu bar.
        case top
        /// Centered on the pointer.
        case around(CGPoint)
        /// Across the whole display, under the menu bar.
        case fullWidth
    }

    static func number(of page: String) -> Int? {
        guard page.hasPrefix("design-"), let n = Int(page.dropFirst(7)), (1...names.count).contains(n) else { return nil }
        return n
    }

    static let ringCenter = CGPoint(x: 720, y: 330)

    static func placement(_ n: Int) -> Placement {
        switch n {
        case 5: .around(ringCenter)
        case 7: .fullWidth
        default: .top
        }
    }

    @ViewBuilder
    static func view(_ n: Int, _ scene: Scene) -> some View {
        switch n {
        case 1: GlassTiles(scene: scene)
        case 2: Neon(scene: scene)
        case 3: Blueprint(scene: scene)
        case 4: IndexCards(scene: scene)
        case 5: Ring(scene: scene)
        case 6: Shelf(scene: scene)
        case 7: Strip(scene: scene)
        case 8: Terminal(scene: scene)
        case 9: Brutalist(scene: scene)
        case 10: Aurora(scene: scene)
        case 11: TinyDisplays(scene: scene)
        case 12: FannedDeck(scene: scene)
        case 13: HUD(scene: scene)
        case 14: Swiss(scene: scene)
        default: Isometric(scene: scene)
        }
    }
}

// MARK: - Shared drawing

/// A layout's zones inside a rectangle, half a gap given up on every inner edge.
private func zoneRects(_ kind: LayoutKind, in r: CGRect, gap: CGFloat) -> [CGRect] {
    kind.zones().map { z in
        var f = CGRect(x: r.minX + CGFloat(z.x) * r.width, y: r.minY + CGFloat(z.y) * r.height,
                       width: CGFloat(z.width) * r.width, height: CGFloat(z.height) * r.height)
        let h = gap / 2, e = 0.0001
        if z.x > e { f.origin.x += h; f.size.width -= h }
        if z.x + z.width < 1 - e { f.size.width -= h }
        if z.y > e { f.origin.y += h; f.size.height -= h }
        if z.y + z.height < 1 - e { f.size.height -= h }
        return f
    }
}

/// Draws one layout's zones; `lit` is the zone under the pointer, if it's on this layout.
private struct Zones: View {
    let kind: LayoutKind
    let lit: Int?
    var inset: CGFloat = 4
    var gap: CGFloat = 3
    var radius: CGFloat = 3
    var fill: Color
    var stroke: Color = .clear
    var lineWidth: CGFloat = 1
    var litFill: Color
    var litStroke: Color = .clear
    var glow: Color? = nil
    var dash: [CGFloat] = []

    var body: some View {
        Canvas { ctx, size in
            let area = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
            for (i, rect) in zoneRects(kind, in: area, gap: gap).enumerated() {
                let path = Path(roundedRect: rect, cornerRadius: radius)
                let on = i == lit
                if on, let glow {
                    var g = ctx
                    g.addFilter(.shadow(color: glow, radius: 7))
                    g.fill(path, with: .color(litFill))
                } else {
                    ctx.fill(path, with: .color(on ? litFill : fill))
                }
                let s = on ? litStroke : stroke
                ctx.stroke(path, with: .color(s), style: StrokeStyle(lineWidth: on ? lineWidth + 0.5 : lineWidth, dash: on ? [] : dash))
            }
        }
    }
}

private extension PaletteDesigns.Scene {
    func lit(_ i: Int) -> Int? { i == lit.entry ? lit.zone : nil }
}

private let thumb = CGSize(width: 112, height: 62)

private extension Color {
    init(hex: UInt32, _ alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

// MARK: - 1 Glass Tiles

private struct GlassTiles: View {
    let scene: PaletteDesigns.Scene
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        HStack(spacing: 10) {
            ForEach(Array(scene.kinds.enumerated()), id: \.offset) { i, kind in
                let on = i == scene.lit.entry
                VStack(spacing: 7) {
                    Zones(kind: kind, lit: scene.lit(i), inset: 6, gap: 4, radius: 6,
                          fill: dark ? .white.opacity(0.16) : .black.opacity(0.11), litFill: .accentColor, glow: .accentColor.opacity(0.8))
                        .frame(width: thumb.width, height: thumb.height)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(dark ? 0.06 : 0.35)))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(on ? Color.accentColor.opacity(0.7) : .white.opacity(dark ? 0.12 : 0.6), lineWidth: on ? 1.5 : 1))
                        .scaleEffect(on ? 1.06 : 1)
                    Text(scene.titles[i]).font(.system(size: 11, weight: on ? .semibold : .medium))
                        .foregroundStyle(on ? .primary : .secondary)
                }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        // Liquid Glass in the app; the frosted fill stands in for it in snapshots, where a
        // tinted glass effect hid the tiles.
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(dark ? Color(hex: 0x24242A, 0.82) : Color(hex: 0xFFFFFF, 0.72)))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(dark ? 0.15 : 0.7), lineWidth: 1))
        .shadow(color: .black.opacity(dark ? 0.45 : 0.18), radius: 20, y: 10)
    }
}

// MARK: - 2 Neon

private struct Neon: View {
    let scene: PaletteDesigns.Scene
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let line = dark ? Color(hex: 0x3DF5FF) : Color(hex: 0x5B2BFF)
        let hot = dark ? Color(hex: 0xFF2E9A) : Color(hex: 0xFF1F7A)
        HStack(spacing: 14) {
            ForEach(Array(scene.kinds.enumerated()), id: \.offset) { i, kind in
                let on = i == scene.lit.entry
                VStack(spacing: 8) {
                    Zones(kind: kind, lit: scene.lit(i), inset: 5, gap: 5, radius: 2,
                          fill: line.opacity(dark ? 0.06 : 0.05), stroke: line.opacity(on ? 1 : 0.75), lineWidth: 1.2,
                          litFill: hot, litStroke: hot, glow: hot)
                        .frame(width: thumb.width, height: thumb.height)
                        .shadow(color: line.opacity(dark ? 0.6 : 0.25), radius: on ? 8 : 4)
                    Text(scene.titles[i].uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.2)
                        .foregroundStyle(on ? hot : line.opacity(0.85))
                        .shadow(color: (on ? hot : line).opacity(dark ? 0.8 : 0.2), radius: 4)
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18).fill(dark ? Color(hex: 0x0B0820, 0.94) : Color(hex: 0xFBF8FF, 0.95)))
        .overlay(RoundedRectangle(cornerRadius: 18)
            .strokeBorder(LinearGradient(colors: [hot, line], startPoint: .leading, endPoint: .trailing), lineWidth: 1.5))
        .shadow(color: hot.opacity(dark ? 0.45 : 0.25), radius: 18)
    }
}

// MARK: - 3 Blueprint

private struct Blueprint: View {
    let scene: PaletteDesigns.Scene
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let paper = dark ? Color(hex: 0x0D2B52) : Color(hex: 0x1F5AA6)
        let ink = Color.white
        HStack(spacing: 16) {
            ForEach(Array(scene.kinds.enumerated()), id: \.offset) { i, kind in
                let on = i == scene.lit.entry
                VStack(alignment: .leading, spacing: 6) {
                    Zones(kind: kind, lit: scene.lit(i), inset: 3, gap: 4, radius: 0,
                          fill: .clear, stroke: ink.opacity(0.85), lineWidth: 1,
                          litFill: ink.opacity(0.35), litStroke: ink, dash: [3, 2])
                        .frame(width: thumb.width, height: thumb.height)
                        .overlay(Rectangle().strokeBorder(ink.opacity(on ? 0.9 : 0.4), lineWidth: 0.75))
                    Text(String(format: "%02d  ", i + 1) + scene.titles[i].uppercased())
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced)).tracking(0.8)
                        .foregroundStyle(ink.opacity(on ? 1 : 0.7))
                }
            }
        }
        .padding(20)
        .background(
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(paper))
                var p = Path()
                for x in stride(from: 0, through: size.width, by: 10) { p.move(to: .init(x: x, y: 0)); p.addLine(to: .init(x: x, y: size.height)) }
                for y in stride(from: 0, through: size.height, by: 10) { p.move(to: .init(x: 0, y: y)); p.addLine(to: .init(x: size.width, y: y)) }
                ctx.stroke(p, with: .color(.white.opacity(0.07)), lineWidth: 0.5)
            }
        )
        .overlay(alignment: .topTrailing) {
            Text("GRIDLOCK · SHEET A-1").font(.system(size: 7, weight: .semibold, design: .monospaced))
                .foregroundStyle(ink.opacity(0.6)).padding(6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
    }
}

// MARK: - 4 Index Cards

private struct IndexCards: View {
    let scene: PaletteDesigns.Scene
    @Environment(\.colorScheme) private var scheme
    private let tilt: [Double] = [-3, 2, -1.5, 2.5, -2, 1.5, -2.5]

    var body: some View {
        let dark = scheme == .dark
        let card = dark ? Color(hex: 0x2C2924) : Color(hex: 0xFFFDF4)
        let pencil = dark ? Color(hex: 0xC9C2B4) : Color(hex: 0x6F6A60)
        let marker = dark ? Color(hex: 0xF2CF3D, 0.85) : Color(hex: 0xFFE24A)
        HStack(spacing: 14) {
            ForEach(Array(scene.kinds.enumerated()), id: \.offset) { i, kind in
                let on = i == scene.lit.entry
                VStack(spacing: 6) {
                    Zones(kind: kind, lit: scene.lit(i), inset: 2, gap: 4, radius: 2,
                          fill: pencil.opacity(0.08), stroke: pencil.opacity(0.7), lineWidth: 1,
                          litFill: marker, litStroke: pencil)
                        .frame(width: 100, height: 56)
                    Text(scene.titles[i]).font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(pencil)
                }
                .padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6).fill(card)
                        .overlay(alignment: .top) { Rectangle().fill(Color(hex: 0xE5484D, 0.55)).frame(height: 1).padding(.top, 6) }
                )
                .shadow(color: .black.opacity(dark ? 0.55 : 0.22), radius: on ? 12 : 5, y: on ? 8 : 3)
                .rotationEffect(.degrees(on ? 0 : tilt[i % tilt.count]))
                .offset(y: on ? 10 : 0)
                .scaleEffect(on ? 1.08 : 1)
                .zIndex(on ? 1 : 0)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 16)
    }
}

// MARK: - 5 Ring

private struct Ring: View {
    let scene: PaletteDesigns.Scene
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let n = scene.kinds.count
        let radius: CGFloat = 158
        let size: CGFloat = 430
        ZStack {
            Circle().strokeBorder(dark ? Color(hex: 0x1E1E22, 0.9) : Color(hex: 0xF7F7FA, 0.92), lineWidth: 104)
                .overlay(Circle().strokeBorder((dark ? Color.white : Color.black).opacity(0.08), lineWidth: 1))
                .frame(width: radius * 2 + 104, height: radius * 2 + 104)
                .shadow(color: .black.opacity(dark ? 0.5 : 0.22), radius: 22, y: 10)
            ForEach(Array(scene.kinds.enumerated()), id: \.offset) { i, kind in
                let on = i == scene.lit.entry
                let angle = Angle.degrees(-90 + Double(i) * 360 / Double(n))
                Zones(kind: kind, lit: scene.lit(i), inset: 5, gap: 3, radius: 4,
                      fill: (dark ? Color.white : Color.black).opacity(0.14), litFill: .accentColor, glow: .accentColor)
                    .frame(width: 86, height: 50)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(dark ? Color(hex: 0x2E2E34) : .white))
                    .shadow(color: .black.opacity(on ? 0.35 : 0.12), radius: on ? 10 : 3, y: 2)
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(on ? Color.accentColor : .clear, lineWidth: 2))
                    .scaleEffect(on ? 1.22 : 1)
                    .offset(x: cos(angle.radians) * radius, y: sin(angle.radians) * radius)
            }
            VStack(spacing: 3) {
                Text(scene.titles[scene.lit.entry]).font(.system(size: 15, weight: .semibold))
                Text("Zone 3 of 3").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(width: 140, height: 140)
            .background(Circle().fill(dark ? Color(hex: 0x2A2A30) : .white))
            .overlay(Circle().strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1.5))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 6 Shelf

private struct Shelf: View {
    let scene: PaletteDesigns.Scene
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(Array(scene.kinds.enumerated()), id: \.offset) { i, kind in
                    let d = abs(i - scene.lit.entry)
                    let scale: CGFloat = d == 0 ? 1.45 : d == 1 ? 1.18 : 1
                    VStack(spacing: 2) {
                        Zones(kind: kind, lit: scene.lit(i), inset: 4, gap: 3, radius: 4,
                              fill: (dark ? Color.white : Color.black).opacity(0.16), litFill: .accentColor)
                            .frame(width: 66 * scale, height: 37 * scale)
                            .background(RoundedRectangle(cornerRadius: 9 * scale, style: .continuous)
                                .fill(LinearGradient(colors: dark ? [Color(hex: 0x3A3A3F), Color(hex: 0x232326)] : [.white, Color(hex: 0xE9E9EE)],
                                                     startPoint: .top, endPoint: .bottom)))
                            .shadow(color: .black.opacity(0.3), radius: 4, y: 3)
                            .overlay(alignment: .top) {
                                if d == 0 {
                                    Text(scene.titles[i]).font(.system(size: 12, weight: .semibold)).fixedSize()
                                        .padding(.horizontal, 10).padding(.vertical, 4)
                                        .background(Capsule().fill(dark ? Color(hex: 0x3A3A40) : .white).shadow(color: .black.opacity(0.2), radius: 4, y: 2))
                                        .offset(y: -32)
                                }
                            }
                        Circle().fill(Color.primary.opacity(d == 0 ? 0.7 : 0)).frame(width: 4, height: 4)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 40).padding(.bottom, 4)
            .background(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: dark ? [Color(hex: 0x3B3B42, 0.92), Color(hex: 0x232328, 0.95)] : [Color(hex: 0xFFFFFF, 0.85), Color(hex: 0xDADAE2, 0.9)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(dark ? 0.12 : 0.8), lineWidth: 1))
                    .frame(height: 64)
                    .shadow(color: .black.opacity(dark ? 0.45 : 0.2), radius: 16, y: 8)
            }
        }
    }
}

// MARK: - 7 Strip

private struct Strip: View {
    let scene: PaletteDesigns.Scene
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        HStack(spacing: 22) {
            Image(systemName: "square.grid.3x1.below.line.grid.1x2").font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
            ForEach(Array(scene.kinds.enumerated()), id: \.offset) { i, kind in
                let on = i == scene.lit.entry
                HStack(spacing: 9) {
                    Zones(kind: kind, lit: scene.lit(i), inset: 3, gap: 2, radius: 2.5,
                          fill: (dark ? Color.white : Color.black).opacity(0.18), litFill: .accentColor)
                        .frame(width: 70, height: 39)
                        .background(RoundedRectangle(cornerRadius: 6).fill((dark ? Color.white : Color.black).opacity(0.05)))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(on ? Color.accentColor : .clear, lineWidth: 1.5))
                    Text(scene.titles[i]).font(.system(size: 11, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? .primary : .secondary).fixedSize()
                }
            }
        }
        .frame(width: 1440, height: 58)
        .background(.bar)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.accentColor).frame(height: 2) }
    }
}

// MARK: - 8 Terminal

private struct Terminal: View {
    let scene: PaletteDesigns.Scene
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let bg = dark ? Color(hex: 0x070C08) : Color(hex: 0xF6EFD9)
        let ink = dark ? Color(hex: 0x3BFF74) : Color(hex: 0x3B2F1E)
        let mono = Font.system(size: 10, weight: .medium, design: .monospaced)
        VStack(alignment: .leading, spacing: 10) {
            Text("gridlock@palette:~$ snap --into ▌").font(mono).foregroundStyle(ink.opacity(0.8))
            HStack(spacing: 12) {
                ForEach(Array(scene.kinds.enumerated()), id: \.offset) { i, kind in
                    let on = i == scene.lit.entry
                    VStack(alignment: .leading, spacing: 5) {
                        Zones(kind: kind, lit: scene.lit(i), inset: 3, gap: 4, radius: 0,
                              fill: .clear, stroke: ink.opacity(on ? 1 : 0.65), lineWidth: 1,
                              litFill: ink, litStroke: ink, glow: dark ? ink : nil)
                            .frame(width: 104, height: 56)
                        Text("[\(i + 1)] " + scene.titles[i].lowercased()).font(mono)
                            .foregroundStyle(on ? bg : ink.opacity(0.8))
                            .padding(.horizontal, 2)
                            .background(on ? ink : .clear)
                    }
                }
            }
        }
        .padding(16)
        .background(bg)
        .overlay(
            Canvas { ctx, size in
                guard dark else { return }
                for y in stride(from: 0, through: size.height, by: 3) {
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(0.25)))
                }
            }.allowsHitTesting(false)
        )
        .overlay(Rectangle().strokeBorder(ink.opacity(0.5), lineWidth: 1))
        .shadow(color: dark ? ink.opacity(0.25) : .black.opacity(0.25), radius: 14)
    }
}

// MARK: - 9 Brutalist

private struct Brutalist: View {
    let scene: PaletteDesigns.Scene
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let panel = dark ? Color(hex: 0x161616) : Color(hex: 0xFFE600)
        let line = dark ? Color(hex: 0xF5F3EA) : .black
        let tile = dark ? Color(hex: 0x2A2A2A) : .white
        let hit = dark ? Color(hex: 0xFF4D2E) : Color(hex: 0x2443FF)
        HStack(spacing: 14) {
            ForEach(Array(scene.kinds.enumerated()), id: \.offset) { i, kind in
                let on = i == scene.lit.entry
                VStack(alignment: .leading, spacing: 6) {
                    Zones(kind: kind, lit: scene.lit(i), inset: 0, gap: 0, radius: 0,
                          fill: tile, stroke: line, lineWidth: 2, litFill: hit, litStroke: line)
                        .frame(width: thumb.width, height: thumb.height)
                        .overlay(Rectangle().strokeBorder(line, lineWidth: 3))
                        .background(Rectangle().fill(line).offset(x: on ? 7 : 4, y: on ? 7 : 4))
                        .offset(x: on ? -3 : 0, y: on ? -3 : 0)
                    Text(scene.titles[i].uppercased()).font(.system(size: 10, weight: .black)).foregroundStyle(line)
                }
            }
        }
        .padding(20)
        .background(panel)
        .overlay(Rectangle().strokeBorder(line, lineWidth: 4))
        .background(Rectangle().fill(line).offset(x: 10, y: 10))
    }
}

// MARK: - 10 Aurora

private struct Aurora: View {
    let scene: PaletteDesigns.Scene
    @Environment(\.colorScheme) private var scheme
    private let hues: [[UInt32]] = [[0x7B2FF7, 0xF107A3], [0x00C6FF, 0x0072FF], [0xF7971E, 0xFFD200], [0x11998E, 0x38EF7D],
                                    [0xFC466B, 0x3F5EFB], [0xEE0979, 0xFF6A00], [0x8E2DE2, 0x4A00E0]]

    var body: some View {
        let dark = scheme == .dark
        HStack(spacing: 12) {
            ForEach(Array(scene.kinds.enumerated()), id: \.offset) { i, kind in
                let on = i == scene.lit.entry
                let pair = hues[i % hues.count]
                VStack(spacing: 7) {
                    Zones(kind: kind, lit: scene.lit(i), inset: 6, gap: 4, radius: 6,
                          fill: .white.opacity(0.28), stroke: .white.opacity(0.35), lineWidth: 0.75,
                          litFill: .white.opacity(0.95), glow: .white)
                        .frame(width: thumb.width, height: thumb.height)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(colors: [Color(hex: pair[0], dark ? 0.85 : 0.7), Color(hex: pair[1], dark ? 0.85 : 0.7)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing)))
                        .shadow(color: Color(hex: pair[0]).opacity(on ? 0.7 : 0.25), radius: on ? 14 : 6, y: 4)
                        .scaleEffect(on ? 1.07 : 1)
                    Text(scene.titles[i]).font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(on ? .primary : .secondary)
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white.opacity(dark ? 0.12 : 0.6), lineWidth: 1))
    }
}

// MARK: - 11 Tiny Displays

private struct TinyDisplays: View {
    let scene: PaletteDesigns.Scene
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        HStack(alignment: .top, spacing: 14) {
            ForEach(Array(scene.kinds.enumerated()), id: \.offset) { i, kind in
                let on = i == scene.lit.entry
                VStack(spacing: 0) {
                    MiniScreen(kind: kind, lit: scene.lit(i))
                        .frame(width: 104, height: 60)
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color(hex: 0x1C1C1E)))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(on ? Color.accentColor : .white.opacity(0.08), lineWidth: on ? 2 : 1))
                    Path { p in
                        p.move(to: .init(x: 46, y: 0)); p.addLine(to: .init(x: 66, y: 0))
                        p.addLine(to: .init(x: 72, y: 10)); p.addLine(to: .init(x: 40, y: 10)); p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [Color(hex: 0xB8B8BE), Color(hex: 0x8E8E93)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 112, height: 10)
                    Text(scene.titles[i]).font(.system(size: 10.5, weight: on ? .semibold : .medium))
                        .foregroundStyle(on ? .primary : .secondary).padding(.top, 5)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(dark ? Color(hex: 0x2B2B30, 0.92) : Color(hex: 0xF4F4F7, 0.94)))
        .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
    }
}

/// A tiny desktop: wallpaper, and each zone as a little window with traffic lights.
private struct MiniScreen: View {
    let kind: LayoutKind
    let lit: Int?

    var body: some View {
        Canvas { ctx, size in
            let r = CGRect(origin: .zero, size: size)
            ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .linearGradient(
                Gradient(colors: [Color(hex: 0x4F7BD9), Color(hex: 0xC78BC8)]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
            for (i, z) in zoneRects(kind, in: r.insetBy(dx: 3, dy: 5), gap: 3).enumerated() {
                let on = i == lit
                ctx.fill(Path(roundedRect: z, cornerRadius: 2.5), with: .color(on ? .accentColor : .white.opacity(0.92)))
                ctx.fill(Path(CGRect(x: z.minX, y: z.minY, width: z.width, height: 5)), with: .color(on ? .white.opacity(0.25) : Color(hex: 0xE4E4E8)))
                for (j, c) in [Color(hex: 0xFF5F57), Color(hex: 0xFEBC2E), Color(hex: 0x28C840)].enumerated() {
                    ctx.fill(Path(ellipseIn: CGRect(x: z.minX + 2 + CGFloat(j) * 3, y: z.minY + 1.5, width: 2, height: 2)), with: .color(c))
                }
            }
        }
    }
}

// MARK: - 12 Fanned Deck

private struct FannedDeck: View {
    let scene: PaletteDesigns.Scene
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let n = scene.kinds.count
        ZStack {
            ForEach(Array(scene.kinds.enumerated()), id: \.offset) { i, kind in
                let on = i == scene.lit.entry
                let t = Double(i) - Double(n - 1) / 2
                VStack(spacing: 8) {
                    Zones(kind: kind, lit: scene.lit(i), inset: 0, gap: 4, radius: 4,
                          fill: (dark ? Color.white : Color.black).opacity(0.12), litFill: .accentColor, glow: .accentColor)
                        .frame(width: 104, height: 58)
                    Text(scene.titles[i]).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(dark ? Color(hex: 0x2C2C30) : .white))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? Color.accentColor : (dark ? Color.white : Color.black).opacity(0.1), lineWidth: on ? 2 : 1))
                .shadow(color: .black.opacity(on ? 0.4 : 0.2), radius: on ? 16 : 6, y: on ? 10 : 3)
                .rotationEffect(.degrees(on ? 0 : t * 7), anchor: .init(x: 0.5, y: 2.6))
                .offset(x: t * 92, y: on ? 26 : abs(t) * 6)
                .scaleEffect(on ? 1.12 : 1)
                .zIndex(on ? 10 : -abs(t))
            }
        }
        .frame(width: 780, height: 210)
    }
}

// MARK: - 13 HUD

private struct HUD: View {
    let scene: PaletteDesigns.Scene
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let c = dark ? Color(hex: 0x4FF3E8) : Color(hex: 0x00707C)
        let mono = Font.system(size: 8.5, weight: .semibold, design: .monospaced)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("GRIDLOCK // LAYOUT SELECT").font(mono).tracking(1.5)
                Spacer()
                Text("TARGET: COL×3 · Z3 · 853×787").font(mono).tracking(1)
            }
            .foregroundStyle(c)
            HStack(spacing: 14) {
                ForEach(Array(scene.kinds.enumerated()), id: \.offset) { i, kind in
                    let on = i == scene.lit.entry
                    VStack(alignment: .leading, spacing: 5) {
                        Zones(kind: kind, lit: scene.lit(i), inset: 6, gap: 4, radius: 0,
                              fill: c.opacity(0.06), stroke: c.opacity(on ? 0.9 : 0.5), lineWidth: 0.75,
                              litFill: c.opacity(0.45), litStroke: c, glow: dark ? c : nil)
                            .frame(width: thumb.width, height: thumb.height)
                            .overlay(Brackets().stroke(c.opacity(on ? 1 : 0.6), lineWidth: on ? 1.5 : 1))
                        Text(String(format: "L%02d ", i + 1) + scene.titles[i].uppercased()).font(mono)
                            .foregroundStyle(c.opacity(on ? 1 : 0.65))
                    }
                }
            }
        }
        .padding(18)
        .background((dark ? Color.black : Color.white).opacity(dark ? 0.72 : 0.82))
        .overlay(Brackets(arm: 18).stroke(c, lineWidth: 2))
        .shadow(color: c.opacity(dark ? 0.3 : 0.15), radius: 12)
    }
}

/// Corner brackets, like a viewfinder.
private struct Brackets: Shape {
    var arm: CGFloat = 9
    func path(in r: CGRect) -> Path {
        var p = Path()
        for (corner, dx, dy) in [(CGPoint(x: r.minX, y: r.minY), 1.0, 1.0), (CGPoint(x: r.maxX, y: r.minY), -1, 1),
                                 (CGPoint(x: r.minX, y: r.maxY), 1, -1), (CGPoint(x: r.maxX, y: r.maxY), -1, -1)] {
            p.move(to: CGPoint(x: corner.x + arm * dx, y: corner.y))
            p.addLine(to: corner)
            p.addLine(to: CGPoint(x: corner.x, y: corner.y + arm * dy))
        }
        return p
    }
}

// MARK: - 14 Swiss

private struct Swiss: View {
    let scene: PaletteDesigns.Scene
    @Environment(\.colorScheme) private var scheme
    private let marks = ["½", "⅓", "⅔⅓", "⅓⅔", "¼", "1", "◦"]

    var body: some View {
        let dark = scheme == .dark
        let ink = dark ? Color(hex: 0xF2F2F2) : Color(hex: 0x111111)
        let red = Color(hex: 0xE3000F)
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(scene.kinds.enumerated()), id: \.offset) { i, kind in
                let on = i == scene.lit.entry
                VStack(alignment: .leading, spacing: 8) {
                    Text(marks[i % marks.count]).font(.system(size: 30, weight: .heavy)).foregroundStyle(on ? red : ink)
                        .frame(height: 34, alignment: .bottomLeading)
                    Zones(kind: kind, lit: scene.lit(i), inset: 0, gap: 3, radius: 0,
                          fill: .clear, stroke: ink.opacity(0.85), lineWidth: 0.75, litFill: red, litStroke: red)
                        .frame(width: 96, height: 54)
                    Text(scene.titles[i]).font(.system(size: 9.5, weight: .medium)).foregroundStyle(ink.opacity(0.7))
                }
                .padding(.horizontal, 12)
                .overlay(alignment: .leading) { if i > 0 { Rectangle().fill(ink.opacity(0.2)).frame(width: 0.5) } }
            }
        }
        .padding(.vertical, 18).padding(.horizontal, 10)
        .background(dark ? Color(hex: 0x111111) : .white)
        .overlay(alignment: .top) { Rectangle().fill(red).frame(height: 4) }
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
    }
}

// MARK: - 15 Isometric

private struct Isometric: View {
    let scene: PaletteDesigns.Scene
    @Environment(\.colorScheme) private var scheme
    private static let slab = CGSize(width: 92, height: 56)
    /// Turned 45° and squashed to 58%: the usual isometric view, kept on the frame.
    private static let iso = CGAffineTransform(a: 0.707, b: 0.41, c: -0.707, d: 0.41, tx: 0.707 * slab.height, ty: 0)
    private static let box = CGSize(width: 0.707 * (slab.width + slab.height), height: 0.41 * (slab.width + slab.height))

    var body: some View {
        let dark = scheme == .dark
        let top = dark ? Color(hex: 0x555B73) : Color(hex: 0xFAFAFD)
        let side = dark ? Color(hex: 0x23262F) : Color(hex: 0xB9BCCB)
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(scene.kinds.enumerated()), id: \.offset) { i, kind in
                let on = i == scene.lit.entry
                VStack(spacing: 10) {
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 5).fill(side)
                            .frame(width: Self.slab.width, height: Self.slab.height)
                            .transformEffect(Self.iso).offset(y: 9)
                        Zones(kind: kind, lit: scene.lit(i), inset: 5, gap: 4, radius: 2,
                              fill: side.opacity(dark ? 0.7 : 0.45), litFill: .accentColor)
                            .frame(width: Self.slab.width, height: Self.slab.height)
                            .background(RoundedRectangle(cornerRadius: 5).fill(top))
                            .transformEffect(Self.iso)
                    }
                    .frame(width: Self.box.width, height: Self.box.height + 9, alignment: .topLeading)
                    .offset(y: on ? -12 : 0)
                    .shadow(color: .black.opacity(on ? 0.3 : 0.18), radius: on ? 8 : 4, y: on ? 12 : 5)
                    Text(scene.titles[i]).font(.system(size: 10.5, weight: on ? .bold : .medium, design: .rounded))
                        .foregroundStyle(on ? .primary : .secondary)
                }
            }
        }
        .padding(.horizontal, 18).padding(.top, 26).padding(.bottom, 14)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(LinearGradient(colors: dark ? [Color(hex: 0x23263A), Color(hex: 0x15161F)] : [Color(hex: 0xEEF0FA), Color(hex: 0xD6D9EC)],
                                 startPoint: .top, endPoint: .bottom)))
        .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
    }
}
#endif
