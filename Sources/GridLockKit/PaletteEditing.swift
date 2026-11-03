import Foundation

/// The built-in layout families the Palette pane offers. A family plus its count is a
/// `LayoutKind`; the same family can sit in a palette more than once with different counts.
public enum LayoutFamily: String, CaseIterable, Codable, Sendable {
    case columns, rows, grid, split, maximize, center

    public var title: String {
        switch self {
        case .columns: return "Columns"
        case .rows: return "Rows"
        case .grid: return "Grid"
        case .split: return "Split"
        case .maximize: return "Maximize"
        case .center: return "Center"
        }
    }

    /// What adding the family puts in a palette when no other count is free.
    public var starter: LayoutKind {
        switch self {
        case .columns: return .columns(count: 2)
        case .rows: return .rows(count: 2)
        case .grid: return .grid(columns: 2, rows: 2)
        case .split: return .split(lead: 2, parts: 3)
        case .maximize: return .maximize
        case .center: return .center(width: 0.6, height: 0.75)
        }
    }
}

extension LayoutKind {
    /// Counts the Palette pane offers: Columns × 2…6, Rows × 2…4, Grid up to 6 × 6.
    public static let columnCounts = 2...6
    public static let rowCounts = 2...4

    /// The two-column splits, both orders, in thirds and quarters.
    public static let splits: [LayoutKind] = [.split(lead: 2, parts: 3), .split(lead: 1, parts: 3),
                                              .split(lead: 3, parts: 4), .split(lead: 1, parts: 4)]

    /// Nil for a custom layout.
    public var family: LayoutFamily? {
        switch self {
        case .columns: return .columns
        case .rows: return .rows
        case .grid: return .grid
        case .split: return .split
        case .maximize: return .maximize
        case .center: return .center
        case .custom: return nil
        }
    }

    /// The same family with a new count, kept in its range. Families without a count are
    /// returned unchanged.
    public func withCount(_ n: Int) -> LayoutKind {
        switch self {
        case .columns: return .columns(count: min(max(n, Self.columnCounts.lowerBound), Self.columnCounts.upperBound))
        case .rows: return .rows(count: min(max(n, Self.rowCounts.lowerBound), Self.rowCounts.upperBound))
        default: return self
        }
    }

    /// A grid with new counts, kept in range and never a single zone (that's Maximize).
    public func withGrid(columns: Int, rows: Int) -> LayoutKind {
        guard case let .grid(oldColumns, oldRows) = self else { return self }
        let c = min(max(columns, Self.gridRange.lowerBound), Self.gridRange.upperBound)
        let r = min(max(rows, Self.gridRange.lowerBound), Self.gridRange.upperBound)
        return c * r < 2 ? .grid(columns: oldColumns, rows: oldRows) : .grid(columns: c, rows: r)
    }
}

extension Palette {
    /// The layout that adding `family` to a palette puts in: the smallest count the palette
    /// doesn't have yet, so adding Columns to a palette with Halves gives Columns × 3.
    public static func adding(_ family: LayoutFamily, to entries: [PaletteEntry]) -> LayoutKind {
        let present = Set(entries.map(\.kind))
        let candidates: [LayoutKind]
        switch family {
        case .columns: candidates = LayoutKind.columnCounts.map { .columns(count: $0) }
        case .rows: candidates = LayoutKind.rowCounts.map { .rows(count: $0) }
        case .grid: candidates = [.grid(columns: 2, rows: 2), .grid(columns: 3, rows: 2), .grid(columns: 4, rows: 2), .grid(columns: 3, rows: 3)]
        case .split: candidates = LayoutKind.splits
        case .maximize, .center: candidates = []
        }
        return candidates.first { !present.contains($0) } ?? family.starter
    }

    /// `entries` with the entry at `from` moved to sit before index `to` (as SwiftUI's
    /// `onMove` reports it), or inserted when it came from elsewhere.
    public static func moving(_ entries: [PaletteEntry], from source: IndexSet, to destination: Int) -> [PaletteEntry] {
        var result = entries
        let moved = source.sorted().map { entries[$0] }
        let before = source.filter { $0 < destination }.count
        for index in source.sorted(by: >) { result.remove(at: index) }
        result.insert(contentsOf: moved, at: min(max(destination - before, 0), result.count))
        return result
    }
}
