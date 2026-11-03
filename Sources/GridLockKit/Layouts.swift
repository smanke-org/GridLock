import Foundation

/// A rectangle as fractions of a display's usable area (0…1, top-left origin), so one
/// layout fits every display shape.
public struct UnitRect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let full = UnitRect(x: 0, y: 0, width: 1, height: 1)

    /// Smallest side a zone may have, as a fraction of the display.
    public static let minimumSide = 0.05

    public var isUsable: Bool {
        width >= Self.minimumSide && height >= Self.minimumSide
            && x >= 0 && y >= 0 && x + width <= 1.0001 && y + height <= 1.0001
    }
}

/// A way of dividing a display. The built-in families carry their counts, so "Columns × 3"
/// and "Columns × 4" are the same family with different counts, and a palette can hold both.
public enum LayoutKind: Codable, Hashable, Sendable {
    /// One zone, the whole display.
    case maximize
    /// One zone centered, `width` × `height` as fractions of the display.
    case center(width: Double, height: Double)
    /// `count` equal columns.
    case columns(count: Int)
    /// `count` equal rows.
    case rows(count: Int)
    /// `columns` × `rows` equal zones.
    case grid(columns: Int, rows: Int)
    /// Two columns: the first `lead` parts of `parts` wide, the second the rest —
    /// (2, 3) is two-thirds then one-third, (1, 3) one-third then two-thirds.
    case split(lead: Int, parts: Int)
    /// A layout the user drew; its zones live in the library's custom layouts.
    case custom(id: UUID)

    public static let countRange = 2...8
    public static let gridRange = 1...6

    /// The zones, left to right then top to bottom. A custom layout that has been deleted
    /// has none.
    public func zones(custom: [CustomLayout] = []) -> [UnitRect] {
        switch self {
        case .maximize:
            return [.full]
        case let .center(w, h):
            let w = min(max(w, UnitRect.minimumSide), 1), h = min(max(h, UnitRect.minimumSide), 1)
            return [UnitRect(x: (1 - w) / 2, y: (1 - h) / 2, width: w, height: h)]
        case let .columns(n):
            let n = max(n, 1)
            return (0..<n).map { UnitRect(x: Double($0) / Double(n), y: 0, width: 1 / Double(n), height: 1) }
        case let .rows(n):
            let n = max(n, 1)
            return (0..<n).map { UnitRect(x: 0, y: Double($0) / Double(n), width: 1, height: 1 / Double(n)) }
        case let .grid(c, r):
            let c = max(c, 1), r = max(r, 1)
            return (0..<r).flatMap { row in
                (0..<c).map { col in
                    UnitRect(x: Double(col) / Double(c), y: Double(row) / Double(r), width: 1 / Double(c), height: 1 / Double(r))
                }
            }
        case let .split(lead, parts):
            let parts = max(parts, 2), lead = min(max(lead, 1), parts - 1)
            let w = Double(lead) / Double(parts)
            return [UnitRect(x: 0, y: 0, width: w, height: 1), UnitRect(x: w, y: 0, width: 1 - w, height: 1)]
        case let .custom(id):
            return custom.first { $0.id == id }?.zones ?? []
        }
    }

    /// The caption under the palette thumbnail.
    public func title(custom: [CustomLayout] = []) -> String {
        switch self {
        case .maximize: return "Maximize"
        case .center: return "Center"
        case .columns(2): return "Halves"
        case let .columns(n): return "Columns × \(n)"
        case let .rows(n): return "Rows × \(n)"
        case .grid(2, 2): return "Quarters"
        case let .grid(c, r): return "Grid \(c) × \(r)"
        case .split(2, 3): return "Two-Thirds + Third"
        case .split(1, 3): return "Third + Two-Thirds"
        case let .split(lead, parts): return "\(lead)/\(parts) + \(parts - lead)/\(parts)"
        case let .custom(id): return custom.first { $0.id == id }?.name ?? "Missing Layout"
        }
    }
}

/// A layout the user drew in the layout editor.
public struct CustomLayout: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var zones: [UnitRect]
    /// When it was last saved, for settings sync: the newest version wins on every Mac.
    public var modified: Date?

    public init(id: UUID = UUID(), name: String, zones: [UnitRect], modified: Date? = nil) {
        self.id = id
        self.name = name
        self.zones = zones
        self.modified = modified
    }
}

/// One thumbnail in a display's palette. Its place in the palette is its place in the array.
public struct PaletteEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var kind: LayoutKind

    public init(id: UUID = UUID(), kind: LayoutKind) {
        self.id = id
        self.kind = kind
    }
}

public enum Palette {
    /// What a display's palette starts with: halves, thirds, the two-thirds splits, quarters,
    /// maximize and center; wide displays add four columns, portrait ones use rows instead.
    public static func suggested(for grid: GridSpec) -> [PaletteEntry] {
        let kinds: [LayoutKind]
        if grid.rows > grid.columns {
            kinds = [.rows(count: 2), .rows(count: 3), .grid(columns: 2, rows: 2), .maximize, .center(width: 0.8, height: 0.6)]
        } else if grid.columns >= 8 {
            kinds = [.columns(count: 2), .columns(count: 3), .columns(count: 4), .split(lead: 2, parts: 3),
                     .split(lead: 1, parts: 3), .grid(columns: 2, rows: 2), .maximize, .center(width: 0.5, height: 0.8)]
        } else {
            kinds = [.columns(count: 2), .columns(count: 3), .split(lead: 2, parts: 3), .split(lead: 1, parts: 3),
                     .grid(columns: 2, rows: 2), .maximize, .center(width: 0.6, height: 0.75)]
        }
        return kinds.map { PaletteEntry(kind: $0) }
    }
}
