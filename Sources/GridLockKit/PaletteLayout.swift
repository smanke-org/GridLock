import CoreGraphics

/// How the palette shows its undo target: the place to drop a window to undo GridLock's last
/// move of it (Settings › Palette). One choice for every palette.
public enum UndoTargetStyle: String, CaseIterable, Codable, Sendable {
    case none, endTile, dividedEndTile, leadingTile, footerStrip, dropWell
    case sideBubble, cornerButton, hangingLip, previewTile, endCap

    public static let standard = UndoTargetStyle.sideBubble

    public var title: String {
        switch self {
        case .none: "None"
        case .endTile: "End Tile"
        case .dividedEndTile: "Divided End Tile"
        case .leadingTile: "Leading Tile"
        case .footerStrip: "Footer Strip"
        case .dropWell: "Drop Well"
        case .sideBubble: "Side Bubble"
        case .cornerButton: "Corner Button"
        case .hangingLip: "Hanging Lip"
        case .previewTile: "Preview Tile"
        case .endCap: "End Cap"
        }
    }

    /// The words on or under the target while nothing is over it.
    public var caption: String? {
        switch self {
        case .none, .cornerButton: nil
        case .endTile, .dividedEndTile, .leadingTile, .dropWell: "Undo Move"
        case .footerStrip: "Drop Here to Undo"
        case .sideBubble, .hangingLip, .endCap: "Undo"
        case .previewTile: "Put Back"
        }
    }

    /// The words while a window is over the target; too narrow a target keeps its own.
    public func hotCaption(app: String) -> String {
        switch self {
        case .footerStrip: "Undo Move of “\(app)”"
        case .hangingLip, .endCap: caption ?? "Undo"
        default: "Undo “\(app)”"
        }
    }
}

/// One piece of the palette's glass, palette-local, top-left origin.
public struct PaletteShape: Equatable, Sendable {
    public var rect: CGRect
    public var radius: CGFloat

    public init(rect: CGRect, radius: CGFloat) {
        self.rect = rect
        self.radius = radius
    }
}

/// The whole palette: the layouts (`PaletteGeometry`) on the shelf, plus the undo target and
/// the app's name and version, placed the way the chosen `UndoTargetStyle` places them. Some
/// styles put glass outside the shelf (a bubble beside it, a button on its corner, a lip
/// under it), so the palette is the box around every piece; `geometry` is the layouts moved
/// into that box, with its size, so frames and zone hits work as before.
public struct PaletteLayout: Equatable, Sendable {
    public enum VersionSpot: Equatable, Sendable { case leading, trailing, center, vertical }

    public struct Version: Equatable, Sendable {
        public let rect: CGRect
        public let spot: VersionSpot
    }

    public static let radius: CGFloat = 22
    /// The version's line, and how much taller the shelf gets to hold it under the captions.
    public static let versionHeight: CGFloat = 13
    static let versionRoom: CGFloat = 8

    public let style: UndoTargetStyle
    public let geometry: PaletteGeometry
    /// The main glass, holding the layouts.
    public let shelf: CGRect
    /// All the glass, back to front.
    public let shapes: [PaletteShape]
    /// The undo target, when it shows.
    public let undo: CGRect?
    /// The words under the target (some styles write on the target instead).
    public let caption: CGRect?
    /// Hairlines between the layouts and the target or the version.
    public let dividers: [CGRect]
    public let version: Version?

    /// The undo target shows only when `showsUndo` (the window has a move to undo).
    public init(base: PaletteGeometry, style: UndoTargetStyle, showsUndo: Bool, showsVersion: Bool) {
        let pad = PaletteGeometry.padding, sp = PaletteGeometry.spacing, h = PaletteGeometry.thumbnailHeight
        let line = Self.versionHeight
        let tile = base.thumbnails.first?.width ?? 100
        let w = base.size.width, H = base.size.height
        // The right edge of the layouts, and the height of their block without captions' room.
        let blockEnd = w - pad
        let dividerHeight = H - 2 * pad - PaletteGeometry.captionHeight
        let undoShown = showsUndo && style != .none

        var size = base.size
        var offset = CGPoint.zero
        var undo: CGRect?
        var caption: CGRect?
        var dividers: [CGRect] = []
        var version: Version?
        var behind: [PaletteShape] = [], front: [PaletteShape] = []

        func captionUnder(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX - sp / 2 + 1, y: r.maxY + 2, width: r.width + sp - 2, height: 16)
        }
        // The version on a line along the shelf's bottom edge, under the captions.
        func bottomVersion(_ spot: VersionSpot) {
            guard showsVersion else { return }
            size.height += Self.versionRoom
            version = Version(rect: CGRect(x: pad + 4, y: size.height - 5 - line, width: size.width - 2 * pad - 8, height: line), spot: spot)
        }

        switch style {
        case .none:
            bottomVersion(.trailing)
        case .endTile, .dropWell:
            if undoShown {
                undo = CGRect(x: blockEnd + sp, y: pad, width: tile, height: h)
                size.width += tile + sp
            }
            bottomVersion(style == .endTile ? .trailing : .center)
        case .dividedEndTile, .previewTile:
            if undoShown {
                dividers.append(CGRect(x: blockEnd + sp, y: pad + 2, width: 1, height: dividerHeight))
                undo = CGRect(x: blockEnd + 2 * sp + 1, y: pad, width: tile, height: h)
                size.width += tile + 2 * sp + 1
            }
            bottomVersion(.leading)
        case .leadingTile:
            if undoShown {
                undo = CGRect(x: pad, y: pad, width: tile, height: h)
                dividers.append(CGRect(x: pad + tile + sp, y: pad + 2, width: 1, height: dividerHeight))
                offset.x = tile + 2 * sp + 1
                size.width += tile + 2 * sp + 1
            }
            bottomVersion(.trailing)
        case .hangingLip:
            if undoShown {
                undo = CGRect(x: blockEnd + sp, y: pad, width: 44, height: h)
                size.width += 44 + sp
            }
            if showsVersion {
                // A lip under the shelf's middle, its top hidden behind the shelf.
                let lip: CGFloat = 112
                behind.append(PaletteShape(rect: CGRect(x: (size.width - lip) / 2, y: size.height - 10, width: lip, height: 28), radius: 9))
                version = Version(rect: CGRect(x: (size.width - lip) / 2, y: size.height + 2, width: lip, height: line), spot: .center)
            }
        case .endCap:
            if showsVersion {
                // Up the left edge, in a strip of its own.
                version = Version(rect: CGRect(x: 0, y: 0, width: 18, height: H), spot: .vertical)
                dividers.append(CGRect(x: 18, y: 0, width: 1, height: H))
                offset.x = 19
                size.width += 19
            }
            if undoShown {
                dividers.append(CGRect(x: size.width, y: 0, width: 1, height: H))
                undo = CGRect(x: size.width + 1, y: 0, width: 64, height: H)
                size.width += 65
            }
        case .footerStrip:
            if undoShown || showsVersion {
                let pill = CGSize(width: 200, height: 26)
                size.width = max(size.width, 2 * pad + (undoShown ? pill.width : 0) + (showsVersion ? 110 : 0))
                offset.x = (size.width - w) / 2
                let top = H - pad + 2
                dividers.append(CGRect(x: pad, y: top, width: size.width - 2 * pad, height: 1))
                let row = top + 9
                if undoShown { undo = CGRect(x: size.width - pad - pill.width, y: row, width: pill.width, height: pill.height) }
                if showsVersion {
                    version = Version(rect: CGRect(x: pad + 4, y: row + (pill.height - line) / 2,
                                                   width: size.width - 2 * pad - 8 - (undoShown ? pill.width : 0), height: line), spot: .leading)
                }
                size.height = row + pill.height + pad - 2
            }
        case .sideBubble:
            if showsVersion {
                size.height += 10
                offset.y = 10
                version = Version(rect: CGRect(x: pad + 4, y: 5, width: size.width - 2 * pad - 8, height: line), spot: .trailing)
            }
            if undoShown {
                // A round bubble beside the shelf, level with the layouts, its words in a
                // small capsule under it.
                let d: CGFloat = 58, wordsWidth: CGFloat = 96
                let center = CGPoint(x: size.width + 10 + wordsWidth / 2, y: offset.y + pad + h / 2)
                let bubble = CGRect(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d)
                let words = CGRect(x: center.x - wordsWidth / 2, y: bubble.maxY + 5, width: wordsWidth, height: 18)
                undo = bubble
                caption = words
                front += [PaletteShape(rect: bubble, radius: d / 2), PaletteShape(rect: words, radius: 9)]
            }
        case .cornerButton:
            bottomVersion(.trailing)
            if undoShown {
                let button = CGRect(x: size.width - 22, y: -14, width: 36, height: 36)
                undo = button
                front.append(PaletteShape(rect: button, radius: 18))
            }
        }
        if caption == nil, let undo, [.endTile, .dividedEndTile, .leadingTile, .dropWell, .previewTile, .hangingLip].contains(style) {
            caption = captionUnder(undo)
        }

        // Everything into one box with its top-left at zero.
        let shelf = CGRect(origin: .zero, size: size)
        let box = (behind + front).reduce(shelf) { $0.union($1.rect) }
        let dx = -box.minX, dy = -box.minY
        func moved(_ r: CGRect) -> CGRect { r.offsetBy(dx: dx, dy: dy) }
        self.style = style
        self.shelf = moved(shelf)
        shapes = behind.map { PaletteShape(rect: moved($0.rect), radius: $0.radius) }
            + [PaletteShape(rect: moved(shelf), radius: Self.radius)]
            + front.map { PaletteShape(rect: moved($0.rect), radius: $0.radius) }
        self.undo = undo.map(moved)
        self.caption = caption.map(moved)
        self.dividers = dividers.map(moved)
        self.version = version.map { Version(rect: moved($0.rect), spot: $0.spot) }
        geometry = PaletteGeometry(thumbnails: base.thumbnails.map { $0.offsetBy(dx: offset.x + dx, dy: offset.y + dy) },
                                   size: box.size)
    }

    /// Whether a palette-local point is on the undo target or its words, give or take a little.
    public func isOnUndo(_ point: CGPoint) -> Bool {
        guard let undo else { return false }
        let area = caption.map { undo.union($0) } ?? undo
        return area.insetBy(dx: -6, dy: -6).contains(point)
    }
}
