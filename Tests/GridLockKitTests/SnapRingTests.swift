import CoreGraphics
import Testing
@testable import GridLockKit

@Suite struct SnapRingTests {
    @Test func centerWithinRadius() {
        #expect(SnapRingPick(offset: CGVector(dx: 5, dy: -10)) == .center)
        #expect(SnapRingPick.center.zone == UnitRect(x: 0, y: 0, width: 1, height: 1))
    }

    @Test func eightWedges() {
        let cases: [(CGFloat, CGFloat, SnapRingDirection)] = [
            (50, 0, .right), (40, 40, .bottomRight), (0, 50, .bottom), (-40, 40, .bottomLeft),
            (-50, 0, .left), (-40, -40, .topLeft), (0, -50, .top), (40, -40, .topRight),
            // Just either side of a boundary (22.5°).
            (50, 19, .right), (50, 22, .bottomRight), (-50, -1, .left),
        ]
        for (dx, dy, direction) in cases {
            #expect(SnapRingPick(offset: CGVector(dx: dx, dy: dy)) == .wedge(direction, far: false), "\(dx),\(dy)")
        }
    }

    @Test func tiers() {
        #expect(SnapRingPick(offset: CGVector(dx: -60, dy: 0)).zone == UnitRect(x: 0, y: 0, width: 0.5, height: 1))
        #expect(SnapRingPick(offset: CGVector(dx: -120, dy: 0)) == .wedge(.left, far: true))
        #expect(SnapRingPick(offset: CGVector(dx: 120, dy: 0)).zone == UnitRect(x: 1 - 1.0 / 3, y: 0, width: 1.0 / 3, height: 1))
        #expect(SnapRingPick(offset: CGVector(dx: 50, dy: 50)).zone == UnitRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))
        #expect(SnapRingPick(offset: CGVector(dx: -100, dy: -100)).zone == UnitRect(x: 0, y: 0, width: 1.0 / 3, height: 0.5))
    }
}
