import CoreGraphics
import Foundation

/// The geometry behind the layout editor's canvas. Points are fractions of the canvas
/// (0…1, top-left origin), the same space zones are stored in.
public enum LayoutCanvas {
    /// The snapping grid: zones snap to twelfths unless snapping is off.
    public static let divisions = 12

    public enum Handle: Sendable { case left, right, top, bottom, body }

    static func snap(_ value: Double, _ divisions: Int?) -> Double {
        let v = min(max(value, 0), 1)
        guard let divisions, divisions > 0 else { return v }
        return (v * Double(divisions)).rounded() / Double(divisions)
    }

    /// The zone a drag from `a` to `b` draws, in either direction, snapped. Nil when it is
    /// smaller than 5% of either side: too small to put a window in.
    public static func zone(from a: CGPoint, to b: CGPoint, divisions: Int? = Self.divisions) -> UnitRect? {
        let x0 = snap(Double(min(a.x, b.x)), divisions), x1 = snap(Double(max(a.x, b.x)), divisions)
        let y0 = snap(Double(min(a.y, b.y)), divisions), y1 = snap(Double(max(a.y, b.y)), divisions)
        let zone = UnitRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        return zone.isUsable ? zone : nil
    }

    /// `zone` with one edge (or the whole zone, for `.body`) dragged by `dx`, `dy`, snapped
    /// and kept on the canvas. Nil when an edge drag would make it smaller than 5%.
    public static func adjusted(_ zone: UnitRect, _ handle: Handle, dx: Double, dy: Double,
                                divisions: Int? = Self.divisions) -> UnitRect? {
        var x0 = zone.x, y0 = zone.y, x1 = zone.x + zone.width, y1 = zone.y + zone.height
        switch handle {
        case .left: x0 = snap(x0 + dx, divisions)
        case .right: x1 = snap(x1 + dx, divisions)
        case .top: y0 = snap(y0 + dy, divisions)
        case .bottom: y1 = snap(y1 + dy, divisions)
        case .body:
            // Moving keeps the size; only the position snaps.
            let nx = min(max(snap(x0 + dx, divisions), 0), 1 - zone.width)
            let ny = min(max(snap(y0 + dy, divisions), 0), 1 - zone.height)
            return UnitRect(x: nx, y: ny, width: zone.width, height: zone.height)
        }
        let result = UnitRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        return result.isUsable ? result : nil
    }

    /// The topmost zone under a point (later zones draw on top), or nil.
    public static func zoneIndex(at point: CGPoint, in zones: [UnitRect]) -> Int? {
        zones.indices.last { i in
            let z = zones[i]
            return Double(point.x) >= z.x && Double(point.x) <= z.x + z.width
                && Double(point.y) >= z.y && Double(point.y) <= z.y + z.height
        }
    }
}

extension CustomLayout {
    /// A layout can be saved with a name and at least one zone, every zone at least 5% of
    /// each side. Zones may overlap.
    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !zones.isEmpty && zones.allSatisfy(\.isUsable)
    }
}
