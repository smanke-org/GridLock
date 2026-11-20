import CoreGraphics
import Foundation

/// What SnapRing picks from where the pointer is relative to the press (docs/SNAPRING.md):
/// the center, or one of 8 wedges in an inner tier (halves and quarters) or an outer tier
/// (thirds).
public enum SnapRingPick: Equatable, Sendable {
    case center
    case wedge(SnapRingDirection, far: Bool)

    /// Pointer within this distance of the press: the center.
    public static let centerRadius: CGFloat = 20
    /// Pointer beyond this distance: the outer tier.
    public static let farRadius: CGFloat = 90

    /// The pick for an offset from the press, in top-left coordinates (y grows downward).
    public init(offset: CGVector) {
        let distance = hypot(offset.dx, offset.dy)
        guard distance >= Self.centerRadius else { self = .center; return }
        self = .wedge(SnapRingDirection(angle: atan2(offset.dy, offset.dx)), far: distance > Self.farRadius)
    }

    /// The zone for this pick; the center is the whole display (Maximize).
    public var zone: UnitRect {
        guard case .wedge(let direction, let far) = self else { return UnitRect(x: 0, y: 0, width: 1, height: 1) }
        return direction.zone(far: far)
    }
}

/// The 8 wedges, clockwise from the right, in screen orientation.
public enum SnapRingDirection: Int, CaseIterable, Sendable {
    case right, bottomRight, bottom, bottomLeft, left, topLeft, top, topRight

    /// The wedge for an angle in radians (0 = right, π/2 = down).
    public init(angle: CGFloat) {
        let step = Int((angle / (.pi / 4)).rounded())
        self = SnapRingDirection(rawValue: ((step % 8) + 8) % 8)!
    }

    /// The wedge's center angle in radians, in top-left coordinates.
    public var angle: CGFloat { CGFloat(rawValue) * .pi / 4 }

    /// Inner tier: a half or a quarter. Outer tier: a third; the corners a third of the
    /// width and half the height.
    public func zone(far: Bool) -> UnitRect {
        let a = far ? 1.0 / 3 : 0.5
        switch self {
        case .left: return UnitRect(x: 0, y: 0, width: a, height: 1)
        case .right: return UnitRect(x: 1 - a, y: 0, width: a, height: 1)
        case .top: return UnitRect(x: 0, y: 0, width: 1, height: a)
        case .bottom: return UnitRect(x: 0, y: 1 - a, width: 1, height: a)
        case .topLeft: return UnitRect(x: 0, y: 0, width: a, height: 0.5)
        case .topRight: return UnitRect(x: 1 - a, y: 0, width: a, height: 0.5)
        case .bottomLeft: return UnitRect(x: 0, y: 0.5, width: a, height: 0.5)
        case .bottomRight: return UnitRect(x: 1 - a, y: 0.5, width: a, height: 0.5)
        }
    }
}
