import CoreGraphics
import Foundation

/// The grid laid over one display: its columns and rows, and the space kept between
/// snapped windows (gap) and around the display's edges (margin), in points.
public struct GridSpec: Codable, Hashable, Sendable {
    public static let columnRange = 1...24
    public static let rowRange = 1...16
    public static let spacingRange = 0.0...64.0

    public var columns: Int
    public var rows: Int
    public var gap: Double
    public var margin: Double

    public init(columns: Int, rows: Int, gap: Double = 0, margin: Double = 0) {
        self.columns = columns
        self.rows = rows
        self.gap = gap
        self.margin = margin
    }

    /// Out-of-range values (a hand-edited file, a future version's limits) pulled back in.
    public var clamped: GridSpec {
        GridSpec(columns: min(max(columns, Self.columnRange.lowerBound), Self.columnRange.upperBound),
                 rows: min(max(rows, Self.rowRange.lowerBound), Self.rowRange.upperBound),
                 gap: min(max(gap, Self.spacingRange.lowerBound), Self.spacingRange.upperBound),
                 margin: min(max(margin, Self.spacingRange.lowerBound), Self.spacingRange.upperBound))
    }

    /// A grid that suits a display of this size: more columns on wide displays, more rows
    /// on portrait ones.
    public static func suggested(for size: CGSize) -> GridSpec {
        guard size.width > 0, size.height > 0 else { return GridSpec(columns: 6, rows: 4) }
        let aspect = size.width / size.height
        switch aspect {
        case ..<1: return GridSpec(columns: 3, rows: 6)
        case ..<1.5: return GridSpec(columns: 4, rows: 4)
        case ..<2.2: return GridSpec(columns: 6, rows: 4)
        default: return GridSpec(columns: 8, rows: 4)
        }
    }
}

/// A block of grid cells: the top-left cell (zero-based) and how many columns and rows it spans.
public struct CellRange: Codable, Hashable, Sendable, CustomStringConvertible {
    public var column: Int
    public var row: Int
    public var columns: Int
    public var rows: Int

    public init(column: Int, row: Int, columns: Int, rows: Int) {
        self.column = column
        self.row = row
        self.columns = columns
        self.rows = rows
    }

    /// The block spanning two cells, in either order — what a drag across the grid selects.
    public init(from a: (column: Int, row: Int), to b: (column: Int, row: Int)) {
        column = min(a.column, b.column)
        row = min(a.row, b.row)
        columns = abs(a.column - b.column) + 1
        rows = abs(a.row - b.row) + 1
    }

    /// "columns 1–4, rows 1–3", counted from one as people do.
    public var description: String {
        func span(_ start: Int, _ count: Int) -> String {
            count == 1 ? "\(start + 1)" : "\(start + 1)–\(start + count)"
        }
        let c = columns == 1 ? "column" : "columns"
        let r = rows == 1 ? "row" : "rows"
        return "\(c) \(span(column, columns)), \(r) \(span(row, rows))"
    }

    /// The same block as fractions of the grid, for placing it like a layout zone.
    public func unitRect(in grid: GridSpec) -> UnitRect {
        UnitRect(x: Double(column) / Double(grid.columns), y: Double(row) / Double(grid.rows),
                 width: Double(columns) / Double(grid.columns), height: Double(rows) / Double(grid.rows))
    }

    public enum Edge: Sendable { case left, right, top, bottom }

    /// Moved by whole cells, stopping at the grid's edges.
    public func moved(dx: Int, dy: Int, in grid: GridSpec) -> CellRange {
        var r = self
        r.column = min(max(column + dx, 0), max(grid.columns - columns, 0))
        r.row = min(max(row + dy, 0), max(grid.rows - rows, 0))
        return r
    }

    /// One edge pushed out (positive `by`) or pulled in (negative), never past the grid
    /// and never smaller than one cell.
    public func resized(_ edge: Edge, by delta: Int, in grid: GridSpec) -> CellRange {
        var r = self
        switch edge {
        case .left:
            let newColumn = min(max(column - delta, 0), column + columns - 1)
            r.columns = columns + (column - newColumn)
            r.column = newColumn
        case .right:
            r.columns = min(max(columns + delta, 1), grid.columns - column)
        case .top:
            let newRow = min(max(row - delta, 0), row + rows - 1)
            r.rows = rows + (row - newRow)
            r.row = newRow
        case .bottom:
            r.rows = min(max(rows + delta, 1), grid.rows - row)
        }
        return r
    }

    /// Kept inside a grid (after the grid shrank, say).
    public func clamped(to grid: GridSpec) -> CellRange {
        let c = min(max(column, 0), grid.columns - 1)
        let r = min(max(row, 0), grid.rows - 1)
        return CellRange(column: c, row: r,
                         columns: min(max(columns, 1), grid.columns - c),
                         rows: min(max(rows, 1), grid.rows - r))
    }

    /// The same share of another grid: columns 4–6 of 6 become 7–12 of 12. Used when a
    /// window moves to a display with a different grid.
    public func mapped(from source: GridSpec, to target: GridSpec) -> CellRange {
        func map(_ start: Int, _ count: Int, _ from: Int, _ to: Int) -> (Int, Int) {
            let s = Int((Double(start) / Double(from) * Double(to)).rounded())
            let e = Int((Double(start + count) / Double(from) * Double(to)).rounded())
            let begin = min(max(s, 0), to - 1)
            return (begin, min(max(e - begin, 1), to - begin))
        }
        let (c, cs) = map(column, columns, source.columns, target.columns)
        let (r, rs) = map(row, rows, source.rows, target.rows)
        return CellRange(column: c, row: r, columns: cs, rows: rs)
    }
}

/// Converting between grid cells, layout zones and window frames on one display. All
/// rectangles are global top-left coordinates.
public enum GridMath {
    /// The display's usable area less the margin: the space cells and zones divide up.
    public static func inner(_ visible: CGRect, margin: Double) -> CGRect {
        let m = min(CGFloat(margin), visible.width / 4, visible.height / 4)
        return visible.insetBy(dx: m, dy: m)
    }

    /// The window frame for a zone. Edges inside the display give up half the gap each, so
    /// two windows in neighboring zones end up exactly one gap apart; edges on the display's
    /// border keep only the margin.
    public static func frame(for zone: UnitRect, visible: CGRect, gap: Double, margin: Double) -> CGRect {
        let area = inner(visible, margin: margin)
        let half = CGFloat(gap) / 2
        let epsilon = 0.0001
        var minX = area.minX + CGFloat(zone.x) * area.width
        var maxX = area.minX + CGFloat(zone.x + zone.width) * area.width
        var minY = area.minY + CGFloat(zone.y) * area.height
        var maxY = area.minY + CGFloat(zone.y + zone.height) * area.height
        if zone.x > epsilon { minX += half }
        if zone.x + zone.width < 1 - epsilon { maxX -= half }
        if zone.y > epsilon { minY += half }
        if zone.y + zone.height < 1 - epsilon { maxY -= half }
        // Rounded to whole points: apps round anyway, and a fractional request reads back
        // as "not where we asked".
        let rect = CGRect(x: minX.rounded(), y: minY.rounded(), width: (maxX - minX).rounded(), height: (maxY - minY).rounded())
        return rect.width >= 1 && rect.height >= 1 ? rect : CGRect(x: minX, y: minY, width: max(maxX - minX, 1), height: max(maxY - minY, 1))
    }

    public static func frame(for cells: CellRange, grid: GridSpec, visible: CGRect) -> CGRect {
        frame(for: cells.unitRect(in: grid), visible: visible, gap: grid.gap, margin: grid.margin)
    }

    /// The cells a window covers, edges rounded to the nearest grid line. Never empty: a
    /// window smaller than a cell gets the cell under its center.
    public static func cells(for frame: CGRect, grid: GridSpec, visible: CGRect) -> CellRange {
        let area = inner(visible, margin: grid.margin)
        let cw = area.width / CGFloat(grid.columns)
        let ch = area.height / CGFloat(grid.rows)
        func line(_ value: CGFloat, _ origin: CGFloat, _ size: CGFloat, _ count: Int) -> Int {
            min(max(Int(((value - origin) / size).rounded()), 0), count)
        }
        var c0 = line(frame.minX, area.minX, cw, grid.columns)
        var c1 = line(frame.maxX, area.minX, cw, grid.columns)
        var r0 = line(frame.minY, area.minY, ch, grid.rows)
        var r1 = line(frame.maxY, area.minY, ch, grid.rows)
        if c1 <= c0 {
            c0 = min(max(Int(((frame.midX - area.minX) / cw).rounded(.down)), 0), grid.columns - 1)
            c1 = c0 + 1
        }
        if r1 <= r0 {
            r0 = min(max(Int(((frame.midY - area.minY) / ch).rounded(.down)), 0), grid.rows - 1)
            r1 = r0 + 1
        }
        return CellRange(column: c0, row: r0, columns: c1 - c0, rows: r1 - r0)
    }

    /// The cell under a point, or nil outside the grid.
    public static func cell(at point: CGPoint, grid: GridSpec, visible: CGRect) -> (column: Int, row: Int)? {
        let area = inner(visible, margin: grid.margin)
        guard area.contains(point) else { return nil }
        let c = Int((point.x - area.minX) / (area.width / CGFloat(grid.columns)))
        let r = Int((point.y - area.minY) / (area.height / CGFloat(grid.rows)))
        return (min(c, grid.columns - 1), min(r, grid.rows - 1))
    }
}
