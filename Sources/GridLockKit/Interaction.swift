import CoreGraphics
import Foundation

// The hands-on parts — the grid's keys and labels, the palette's geometry, the top-edge
// dwell, cycling sizes, the next display, shortcut clashes — as plain values, so the
// overlays only draw and forward events.

public enum GridDirection: Sendable { case left, right, up, down }

/// What a key does to the selection on the grid.
public enum GridKeyAction: Sendable, Equatable {
    /// Arrow: the selection moves one cell.
    case move(GridDirection)
    /// ⇧-arrow: the edge on that side moves out one cell.
    case grow(GridDirection)
    /// ⌥⇧-arrow: the edge facing the other way moves in one cell, so the selection shrinks
    /// toward the arrow.
    case shrink(GridDirection)
}

extension CellRange {
    /// The selection after a key. Never leaves the grid and never shrinks below one cell; at
    /// an edge the key does nothing.
    public func applying(_ action: GridKeyAction, in grid: GridSpec) -> CellRange {
        switch action {
        case .move(.left): return moved(dx: -1, dy: 0, in: grid)
        case .move(.right): return moved(dx: 1, dy: 0, in: grid)
        case .move(.up): return moved(dx: 0, dy: -1, in: grid)
        case .move(.down): return moved(dx: 0, dy: 1, in: grid)
        case .grow(.left): return resized(.left, by: 1, in: grid)
        case .grow(.right): return resized(.right, by: 1, in: grid)
        case .grow(.up): return resized(.top, by: 1, in: grid)
        case .grow(.down): return resized(.bottom, by: 1, in: grid)
        case .shrink(.left): return resized(.right, by: -1, in: grid)
        case .shrink(.right): return resized(.left, by: -1, in: grid)
        case .shrink(.up): return resized(.bottom, by: -1, in: grid)
        case .shrink(.down): return resized(.top, by: -1, in: grid)
        }
    }

    /// "columns 1 to 4, rows 1 to 3", for VoiceOver, which reads "1–4" as "1 4".
    public var spoken: String {
        description.replacingOccurrences(of: "–", with: " to ")
    }
}

public enum GridText {
    /// "1280 × 800".
    public static func size(_ size: CGSize) -> String {
        "\(Int(size.width.rounded())) × \(Int(size.height.rounded()))"
    }

    /// The label on the grid: "Safari · 1280 × 800 · columns 1–4, rows 1–3".
    public static func label(app: String, frame: CGRect, cells: CellRange) -> String {
        "\(app) · \(size(frame.size)) · \(cells)"
    }

    /// What VoiceOver says when the grid opens or the selection changes.
    public static func announcement(grid: GridSpec, cells: CellRange) -> String {
        let c = grid.columns == 1 ? "1 column" : "\(grid.columns) columns"
        let r = grid.rows == 1 ? "1 row" : "\(grid.rows) rows"
        return "Grid, \(c) by \(r), selection \(cells.spoken)"
    }
}

extension ScreenSpace {
    /// A global top-left rectangle in a display's own top-left space, for drawing it in an
    /// overlay that covers the display.
    public static func local(_ rect: CGRect, in display: CGRect) -> CGRect {
        rect.offsetBy(dx: -display.minX, dy: -display.minY)
    }
}

/// Where the palette's thumbnails sit and which zone is under the cursor. Laid out here,
/// not by the view, because the palette never gets the mouse: the cursor is busy dragging
/// another app's window, so hits are worked out from its global position.
public struct PaletteGeometry: Equatable, Sendable {
    public static let padding: CGFloat = 12
    public static let spacing: CGFloat = 12
    public static let captionHeight: CGFloat = 18
    public static let thumbnailHeight: CGFloat = 64
    /// Gap between the top of the display's usable area and the palette.
    public static let drop: CGFloat = 8

    /// Thumbnail rectangles (without captions), palette-local, top-left origin.
    public let thumbnails: [CGRect]
    public let size: CGSize

    /// Thumbnails shaped like the display (`aspect` = width / height), as many to a row as
    /// fit in `maxWidth`, wrapping to more rows rather than scrolling.
    public init(count: Int, aspect: Double, maxWidth: CGFloat) {
        let h = Self.thumbnailHeight
        let w = (h * CGFloat(aspect)).rounded().clamped(to: 72...140)
        let cell = w + Self.spacing
        let fit = max(Int((maxWidth - 2 * Self.padding + Self.spacing) / cell), 1)
        let perRow = max(min(count, fit), 1)
        let rows = max((count + perRow - 1) / perRow, 1)
        let rowHeight = h + Self.captionHeight
        var rects: [CGRect] = []
        for i in 0..<count {
            let row = i / perRow, column = i % perRow
            // A short last row is centered under the full ones.
            let inRow = row == rows - 1 ? count - row * perRow : perRow
            let rowWidth = CGFloat(inRow) * cell - Self.spacing
            let fullWidth = CGFloat(perRow) * cell - Self.spacing
            let x = Self.padding + (fullWidth - rowWidth) / 2 + CGFloat(column) * cell
            let y = Self.padding + CGFloat(row) * (rowHeight + Self.spacing)
            rects.append(CGRect(x: x, y: y, width: w, height: h))
        }
        thumbnails = rects
        size = CGSize(width: CGFloat(perRow) * cell - Self.spacing + 2 * Self.padding,
                      height: CGFloat(rows) * rowHeight + CGFloat(rows - 1) * Self.spacing + 2 * Self.padding)
    }

    /// The palette's frame on a display (global top-left): just below the menu bar, centered
    /// under the cursor, kept on the display.
    public func frame(under cursorX: CGFloat, bounds: CGRect, visible: CGRect) -> CGRect {
        let inset: CGFloat = 8
        let x = min(max(cursorX - size.width / 2, bounds.minX + inset), bounds.maxX - inset - size.width)
        return CGRect(x: x.rounded(), y: visible.minY + Self.drop, width: size.width, height: size.height)
    }

    /// The palette's frame when it slides out of its tab (global top-left): centered on
    /// `centerX`, kept on the display, its top against the menu bar.
    public func frame(hangingFrom visible: CGRect, centerX: CGFloat, bounds: CGRect) -> CGRect {
        var f = frame(under: centerX, bounds: bounds, visible: visible)
        f.origin.y = visible.minY
        return f
    }

    /// Space between the cursor and a palette opened next to it.
    public static let lift: CGFloat = 32

    /// The palette's frame when a held modifier opens it mid-drag (global top-left):
    /// centered on the cursor with its bottom `lift` above it, or below the cursor when
    /// there's no room above, kept inside the display's usable area.
    public func frame(near cursor: CGPoint, visible: CGRect) -> CGRect {
        let inset: CGFloat = 8
        let x = min(max(cursor.x - size.width / 2, visible.minX + inset), visible.maxX - inset - size.width)
        var y = cursor.y - Self.lift - size.height
        if y < visible.minY + inset { y = min(cursor.y + Self.lift, visible.maxY - inset - size.height) }
        return CGRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
    }

    /// The thumbnail and zone under a palette-local point. Zones may overlap (custom layouts):
    /// the smallest one under the point wins, so a small zone inside a big one can be reached.
    public func hit(_ point: CGPoint, zones: [[UnitRect]]) -> (entry: Int, zone: Int)? {
        for (i, rect) in thumbnails.enumerated() where i < zones.count && rect.contains(point) {
            let u = (point.x - rect.minX) / rect.width, v = (point.y - rect.minY) / rect.height
            let candidates = zones[i].indices.filter { z in
                let r = zones[i][z]
                return u >= r.x && u < r.x + r.width + 0.0001 && v >= r.y && v < r.y + r.height + 0.0001
            }
            if let best = candidates.min(by: { zones[i][$0].width * zones[i][$0].height < zones[i][$1].width * zones[i][$1].height }) {
                return (i, best)
            }
        }
        return nil
    }

    /// Whether the palette stays open with the cursor here (global): over it or close to it,
    /// or still at the top of the display. Dragging well away closes it.
    public static func keepsOpen(cursor: CGPoint, palette: CGRect, bounds: CGRect) -> Bool {
        palette.insetBy(dx: -48, dy: -48).contains(cursor) || (bounds.contains(cursor) && cursor.y - bounds.minY <= 48)
    }
}

/// The wait at the top edge before the palette opens: the cursor must stay within `reach`
/// of a display's top for `delay`, so a window flung past the top doesn't open it.
public struct EdgeDwell: Sendable {
    public static let reach: CGFloat = 4
    public static let delay: TimeInterval = 0.15

    private var since: TimeInterval?

    public init() {}

    public static func isAtEdge(_ cursor: CGPoint, bounds: CGRect) -> Bool {
        cursor.x >= bounds.minX && cursor.x < bounds.maxX && cursor.y >= bounds.minY - 1 && cursor.y - bounds.minY <= reach
    }

    /// Feed every cursor sample (and one more when the delay runs out). True once the cursor
    /// has stayed at the edge long enough; leaving the edge starts the wait again.
    public mutating func update(cursor: CGPoint, bounds: CGRect, now: TimeInterval) -> Bool {
        guard Self.isAtEdge(cursor, bounds: bounds) else { since = nil; return false }
        if since == nil { since = now }
        return now - since! >= Self.delay - 0.001
    }

    public mutating func reset() { since = nil }
}

public enum DragCheck {
    /// A window being dragged moves without changing size; a resize from an edge or corner
    /// changes its size, and a click that selects text changes neither.
    public static func isMove(from start: CGRect, to now: CGRect) -> Bool {
        let moved = abs(now.minX - start.minX) > 1 || abs(now.minY - start.minY) > 1
        let sameSize = abs(now.width - start.width) <= 1 && abs(now.height - start.height) <= 1
        return moved && sameSize
    }
}

/// Pressing a half's shortcut again on the same window steps through other sizes on that side.
public struct SizeCycle: Sendable {
    public static let timeout: TimeInterval = 2

    /// The sizes in turn, as fractions of the display, in the order set in Settings.
    public enum Order: String, CaseIterable, Codable, Sendable {
        case halfTwoThirdsThird, halfThirdTwoThirds, off

        public var fractions: [Double] {
            switch self {
            case .halfTwoThirdsThird: return [1.0 / 2, 2.0 / 3, 1.0 / 3]
            case .halfThirdTwoThirds: return [1.0 / 2, 1.0 / 3, 2.0 / 3]
            case .off: return [1.0 / 2]
            }
        }

        public var title: String {
            switch self {
            case .halfTwoThirdsThird: return "Half, Two-Thirds, Third"
            case .halfThirdTwoThirds: return "Half, Third, Two-Thirds"
            case .off: return "Off"
            }
        }
    }

    public enum Side: String, Sendable { case left, right, top, bottom }

    /// The halves that cycle: "left-half" → left, and so on.
    public static func side(forZone name: String) -> Side? {
        switch name {
        case "left-half": return .left
        case "right-half": return .right
        case "top-half": return .top
        case "bottom-half": return .bottom
        default: return nil
        }
    }

    public static func zone(_ side: Side, fraction f: Double) -> UnitRect {
        switch side {
        case .left: return UnitRect(x: 0, y: 0, width: f, height: 1)
        case .right: return UnitRect(x: 1 - f, y: 0, width: f, height: 1)
        case .top: return UnitRect(x: 0, y: 0, width: 1, height: f)
        case .bottom: return UnitRect(x: 0, y: 1 - f, width: 1, height: f)
        }
    }

    private var last: (side: Side, window: String, time: TimeInterval, step: Int)?

    public init() {}

    /// The zone for this press: the first size, or the next one when the same side was
    /// pressed for the same window within `timeout`.
    public mutating func zone(for side: Side, window: String, order: Order, now: TimeInterval) -> UnitRect {
        let sizes = order.fractions
        var step = 0
        if let last, last.side == side, last.window == window, now - last.time < Self.timeout {
            step = (last.step + 1) % sizes.count
        }
        last = (side, window, now, step)
        return Self.zone(side, fraction: sizes[step])
    }
}

public enum DisplayOrder {
    /// The display after `index`, left to right (top to bottom for a column), wrapping.
    public static func next(after index: Int, in displays: [LiveDisplay], step: Int = 1) -> Int {
        guard displays.count > 1, displays.indices.contains(index) else { return index }
        let order = displays.indices.sorted { (displays[$0].bounds.minX, displays[$0].bounds.minY) < (displays[$1].bounds.minX, displays[$1].bounds.minY) }
        let at = order.firstIndex(of: index)!
        return order[((at + step) % order.count + order.count) % order.count]
    }
}

public enum ShortcutClash {
    /// The id of another action already using `key`, if any. Each action's key is looked up
    /// through `keyFor`, so defaults and cleared shortcuts count as they are.
    public static func owner<Key: Equatable>(of key: Key, for id: String, among ids: [String], keyFor: (String) -> Key?) -> String? {
        ids.first { $0 != id && keyFor($0) == key }
    }
}

public enum EdgeTiling {
    /// Whether macOS's "Drag windows to screen edges to tile" is on, from the
    /// `com.apple.WindowManager` domain. On unless it was turned off.
    public static func isOn(_ preferences: [String: Any]) -> Bool {
        (preferences["EnableTilingByEdgeDrag"] as? NSNumber)?.boolValue ?? true
    }
}

extension CGFloat {
    fileprivate func clamped(to range: ClosedRange<CGFloat>) -> CGFloat { Swift.min(Swift.max(self, range.lowerBound), range.upperBound) }
}

/// The palette's tab: the palette's bottom edge, peeking down from under the menu bar at
/// the top center of a display while a window is dragged, as if the rest of the palette were
/// just out of sight. Reaching it slides the whole palette down from there.
public enum PaletteTab {
    /// How much of the palette's bottom edge shows.
    public static let height: CGFloat = 10
    /// How far around the tab the pointer counts as reaching it: a window being dragged is
    /// not a precise pointer.
    public static let reach = (sides: CGFloat(36), below: CGFloat(40))

    /// The tab for a palette hanging from the menu bar (`PaletteGeometry.frame(hangingFrom:)`):
    /// as wide as the palette, `height` tall, against the menu bar.
    public static func frame(palette: CGRect, visible: CGRect) -> CGRect {
        CGRect(x: palette.minX, y: visible.minY, width: palette.width, height: height)
    }

    /// Whether the pointer (global) has reached the tab: on it, beside it, a little below it,
    /// or above it in the menu bar.
    public static func reaches(_ cursor: CGPoint, tab: CGRect) -> Bool {
        cursor.x >= tab.minX - reach.sides && cursor.x <= tab.maxX + reach.sides && cursor.y <= tab.maxY + reach.below
    }
}
