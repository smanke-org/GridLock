import CoreGraphics
import Foundation
import Testing
@testable import GridLockKit

struct GridKeyTests {
    let grid = GridSpec(columns: 6, rows: 4)

    @Test func arrowsMoveAndStopAtEdges() {
        let r = CellRange(column: 0, row: 0, columns: 2, rows: 1)
        #expect(r.applying(.move(.left), in: grid) == r)
        #expect(r.applying(.move(.up), in: grid) == r)
        #expect(r.applying(.move(.right), in: grid) == CellRange(column: 1, row: 0, columns: 2, rows: 1))
        #expect(r.applying(.move(.down), in: grid) == CellRange(column: 0, row: 1, columns: 2, rows: 1))
    }

    @Test func shiftGrowsTowardTheArrow() {
        let r = CellRange(column: 2, row: 1, columns: 1, rows: 1)
        #expect(r.applying(.grow(.left), in: grid) == CellRange(column: 1, row: 1, columns: 2, rows: 1))
        #expect(r.applying(.grow(.right), in: grid) == CellRange(column: 2, row: 1, columns: 2, rows: 1))
        #expect(r.applying(.grow(.up), in: grid) == CellRange(column: 2, row: 0, columns: 1, rows: 2))
        #expect(r.applying(.grow(.down), in: grid) == CellRange(column: 2, row: 1, columns: 1, rows: 2))
    }

    @Test func optionShiftShrinksTowardTheArrow() {
        let r = CellRange(column: 1, row: 1, columns: 3, rows: 2)
        #expect(r.applying(.shrink(.left), in: grid) == CellRange(column: 1, row: 1, columns: 2, rows: 2))
        #expect(r.applying(.shrink(.right), in: grid) == CellRange(column: 2, row: 1, columns: 2, rows: 2))
        #expect(r.applying(.shrink(.up), in: grid) == CellRange(column: 1, row: 1, columns: 3, rows: 1))
        #expect(r.applying(.shrink(.down), in: grid) == CellRange(column: 1, row: 2, columns: 3, rows: 1))
    }

    @Test func neverLeavesTheGridOrShrinksBelowOneCell() {
        let actions: [GridKeyAction] = [.move(.left), .move(.right), .move(.up), .move(.down),
                                        .grow(.left), .grow(.right), .grow(.up), .grow(.down),
                                        .shrink(.left), .shrink(.right), .shrink(.up), .shrink(.down)]
        var r = CellRange(column: 3, row: 2, columns: 1, rows: 1)
        // A long, deterministic mix of keys.
        for i in 0..<500 {
            r = r.applying(actions[(i * 7 + i / 3) % actions.count], in: grid)
            #expect(r.column >= 0 && r.row >= 0 && r.columns >= 1 && r.rows >= 1)
            #expect(r.column + r.columns <= grid.columns && r.row + r.rows <= grid.rows)
        }
    }

    @Test func labelsAndAnnouncements() {
        let cells = CellRange(column: 0, row: 0, columns: 4, rows: 3)
        #expect(GridText.label(app: "Safari", frame: CGRect(x: 0, y: 0, width: 1280, height: 800), cells: cells)
            == "Safari · 1280 × 800 · columns 1–4, rows 1–3")
        #expect(GridText.announcement(grid: grid, cells: cells) == "Grid, 6 columns by 4 rows, selection columns 1 to 4, rows 1 to 3")
    }

    @Test func localToADisplayAboveLeftOfMain() {
        let display = CGRect(x: -1920, y: -1080, width: 1920, height: 1080)
        #expect(ScreenSpace.local(CGRect(x: -1900, y: -1000, width: 100, height: 50), in: display)
            == CGRect(x: 20, y: 80, width: 100, height: 50))
        // AppKit's frame for the same display (bottom-left, main 1440 high) flips back to it.
        let appKit = CGRect(x: -1920, y: 1440, width: 1920, height: 1080)
        #expect(ScreenSpace.flip(appKit, mainHeight: 1440) == display)
    }
}

struct PaletteGeometryTests {
    @Test func opensAboveTheCursorOrBelowWhenThereIsNoRoom() {
        let g = PaletteGeometry(count: 3, aspect: 16.0 / 10, maxWidth: 800)
        let visible = CGRect(x: 0, y: 30, width: 1600, height: 970)
        let above = g.frame(near: CGPoint(x: 800, y: 600), visible: visible)
        #expect(above.maxY == 600 - PaletteGeometry.lift)
        #expect(abs(above.midX - 800) <= 1)
        // Near the top there's no room above: it goes under the cursor instead.
        let below = g.frame(near: CGPoint(x: 800, y: 60), visible: visible)
        #expect(below.minY == 60 + PaletteGeometry.lift)
        // Near a side it stays on the display.
        let side = g.frame(near: CGPoint(x: 5, y: 600), visible: visible)
        #expect(side.minX == 8)
    }

    @Test func wrapsInsteadOfScrolling() {
        let g = PaletteGeometry(count: 7, aspect: 16.0 / 10, maxWidth: 500)
        // 102-pt thumbnails, 114 a step: four fit in 500.
        #expect(g.thumbnails.count == 7)
        #expect(Set(g.thumbnails.map(\.minY)).count == 2)
        #expect(g.size.width <= 500)
        #expect(g.thumbnails.allSatisfy { CGRect(origin: .zero, size: g.size).contains($0) })
    }

    @Test func hitsTheZoneUnderTheCursor() {
        let g = PaletteGeometry(count: 2, aspect: 1.6, maxWidth: 1000)
        let zones = [LayoutKind.columns(count: 2).zones(), LayoutKind.grid(columns: 2, rows: 2).zones()]
        let second = g.thumbnails[1]
        #expect(g.hit(CGPoint(x: g.thumbnails[0].minX + 5, y: g.thumbnails[0].midY), zones: zones)! == (0, 0))
        #expect(g.hit(CGPoint(x: second.maxX - 5, y: second.maxY - 5), zones: zones)! == (1, 3))
        #expect(g.hit(CGPoint(x: 1, y: 1), zones: zones) == nil)
    }

    @Test func smallestOverlappingZoneWins() {
        let g = PaletteGeometry(count: 1, aspect: 1, maxWidth: 400)
        let zones = [[UnitRect.full, UnitRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)]]
        let t = g.thumbnails[0]
        #expect(g.hit(CGPoint(x: t.midX, y: t.midY), zones: zones)! == (0, 1))
        #expect(g.hit(CGPoint(x: t.minX + 2, y: t.minY + 2), zones: zones)! == (0, 0))
    }

    @Test func dropsBelowTheMenuBarAndStaysOnTheDisplay() {
        let g = PaletteGeometry(count: 3, aspect: 1.6, maxWidth: 1000)
        let bounds = CGRect(x: 2560, y: -425, width: 1728, height: 1117)
        let visible = CGRect(x: 2560, y: -392, width: 1728, height: 1084)
        let f = g.frame(under: 4280, bounds: bounds, visible: visible)
        #expect(f.minY == visible.minY + PaletteGeometry.drop)
        #expect(f.maxX <= bounds.maxX && f.minX >= bounds.minX)
    }

    @Test func closesWhenDraggedAway() {
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let palette = CGRect(x: 500, y: 33, width: 400, height: 120)
        #expect(PaletteGeometry.keepsOpen(cursor: CGPoint(x: 700, y: 100), palette: palette, bounds: bounds))
        #expect(PaletteGeometry.keepsOpen(cursor: CGPoint(x: 100, y: 2), palette: palette, bounds: bounds))
        #expect(!PaletteGeometry.keepsOpen(cursor: CGPoint(x: 700, y: 400), palette: palette, bounds: bounds))
    }
}

struct DragTests {
    let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test func opensOnlyAfterDwellingAtTheTopEdge() {
        var dwell = EdgeDwell()
        func at(_ x: CGFloat, _ y: CGFloat, _ t: TimeInterval) -> Bool { dwell.update(cursor: CGPoint(x: x, y: y), bounds: bounds, now: t) }
        #expect(!at(600, 2, 10))
        #expect(!at(610, 3, 10.1))
        #expect(at(620, 4, 10.15))
        // Leaving the edge starts the wait again.
        #expect(!at(620, 5, 10.2))
        #expect(!at(620, 0, 10.25))
        #expect(!at(620, 0, 10.35))
        #expect(at(620, 0, 10.4))
    }

    @Test func edgeBelongsToTheDisplayUnderTheCursor() {
        let side = CGRect(x: 1440, y: -200, width: 1000, height: 800)
        #expect(EdgeDwell.isAtEdge(CGPoint(x: 1500, y: -198), bounds: side))
        #expect(!EdgeDwell.isAtEdge(CGPoint(x: 1500, y: 2), bounds: side))
    }

    @Test func aMoveIsNotAResizeOrAClick() {
        let start = CGRect(x: 100, y: 100, width: 800, height: 600)
        #expect(DragCheck.isMove(from: start, to: start.offsetBy(dx: 30, dy: -10)))
        #expect(!DragCheck.isMove(from: start, to: start))
        #expect(!DragCheck.isMove(from: start, to: CGRect(x: 80, y: 100, width: 820, height: 600)))
    }
}

struct SpeedTests {
    @Test func cycleFollowsTheOrderAndResets() {
        var cycle = SizeCycle()
        func press(_ side: SizeCycle.Side, _ window: String, _ t: TimeInterval, _ order: SizeCycle.Order = .halfTwoThirdsThird) -> UnitRect {
            cycle.zone(for: side, window: window, order: order, now: t)
        }
        #expect(press(.left, "a", 0).width == 0.5)
        #expect(abs(press(.left, "a", 1).width - 2.0 / 3) < 1e-9)
        #expect(abs(press(.left, "a", 2).width - 1.0 / 3) < 1e-9)
        #expect(press(.left, "a", 3).width == 0.5)
        // More than 2 s later, another window, or another side: back to the first size.
        #expect(press(.left, "a", 5.5).width == 0.5)
        _ = press(.left, "a", 6)
        #expect(press(.left, "b", 6.5).width == 0.5)
        #expect(press(.right, "b", 7) == UnitRect(x: 0.5, y: 0, width: 0.5, height: 1))
        #expect(abs(press(.right, "b", 7.5, .halfThirdTwoThirds).x - 2.0 / 3) < 1e-9)
        #expect(press(.right, "b", 8, .off).width == 0.5)
    }

    @Test func nextDisplayGoesLeftToRightAndWraps() {
        func d(_ x: CGFloat) -> LiveDisplay {
            LiveDisplay(key: "\(x)", name: "", isBuiltin: false, isMain: false,
                        bounds: CGRect(x: x, y: 0, width: 100, height: 100), visible: CGRect(x: x, y: 0, width: 100, height: 100))
        }
        let displays = [d(0), d(-100), d(100)]
        #expect(DisplayOrder.next(after: 1, in: displays) == 0)
        #expect(DisplayOrder.next(after: 0, in: displays) == 2)
        #expect(DisplayOrder.next(after: 2, in: displays) == 1)
        #expect(DisplayOrder.next(after: 1, in: displays, step: -1) == 2)
        #expect(DisplayOrder.next(after: 0, in: [d(0)]) == 0)
    }

    @Test func cellsKeepTheirShareOnTheNextDisplay() {
        let six = GridSpec(columns: 6, rows: 4), twelve = GridSpec(columns: 12, rows: 4)
        #expect(CellRange(column: 0, row: 0, columns: 4, rows: 4).mapped(from: six, to: twelve)
            == CellRange(column: 0, row: 0, columns: 8, rows: 4))
    }

    @Test func clashNamesTheOtherAction() {
        let keys = ["grid": "⌃⌥G", "undo": "⌃⌥Z", "zone.left-half": nil as String?]
        let ids = ["grid", "undo", "zone.left-half"]
        #expect(ShortcutClash.owner(of: "⌃⌥G", for: "zone.left-half", among: ids) { keys[$0] ?? nil } == "grid")
        #expect(ShortcutClash.owner(of: "⌃⌥G", for: "grid", among: ids) { keys[$0] ?? nil } == nil)
        #expect(ShortcutClash.owner(of: "⌃⌥X", for: "grid", among: ids) { keys[$0] ?? nil } == nil)
    }

    @Test func edgeTilingIsOnUnlessTurnedOff() {
        #expect(EdgeTiling.isOn([:]))
        #expect(!EdgeTiling.isOn(["EnableTilingByEdgeDrag": NSNumber(value: false)]))
        #expect(EdgeTiling.isOn(["EnableTilingByEdgeDrag": NSNumber(value: 1)]))
    }
}

@Suite struct PaletteTabTests {
    private let visible = CGRect(x: 0, y: 30, width: 2560, height: 1410)
    private let bounds = CGRect(x: 0, y: 0, width: 2560, height: 1440)

    @Test func isThePalettesBottomEdgeAgainstTheMenuBar() {
        let g = PaletteGeometry(count: 7, aspect: 2560.0 / 1410, maxWidth: 900)
        let palette = g.frame(hangingFrom: visible, centerX: bounds.midX, bounds: bounds)
        #expect(palette.minY == visible.minY)
        #expect(abs(palette.midX - 1280) <= 1)
        let tab = PaletteTab.frame(palette: palette, visible: visible)
        #expect(tab.minX == palette.minX && tab.width == palette.width)
        #expect(tab.minY == 30 && tab.height == PaletteTab.height)
    }

    @Test func isReachedOnItBesideItAndJustBelowIt() {
        let tab = CGRect(x: 830, y: 30, width: 900, height: PaletteTab.height)
        #expect(PaletteTab.reaches(CGPoint(x: tab.midX, y: tab.midY), tab: tab))
        #expect(PaletteTab.reaches(CGPoint(x: tab.minX - 30, y: tab.maxY + 30), tab: tab))
        #expect(PaletteTab.reaches(CGPoint(x: tab.midX, y: 5), tab: tab))      // up in the menu bar
        #expect(!PaletteTab.reaches(CGPoint(x: tab.midX, y: tab.maxY + 60), tab: tab))
        #expect(!PaletteTab.reaches(CGPoint(x: tab.maxX + 60, y: tab.midY), tab: tab))
    }
}

struct PaletteLayoutTests {
    private let base = PaletteGeometry(count: 3, aspect: 1.6, maxWidth: 900)

    @Test func noneKeepsTheShelfAndAddsRoomForTheVersion() {
        let plain = PaletteLayout(base: base, style: .none, showsUndo: true, showsVersion: false)
        #expect(plain.geometry == base)
        #expect(plain.undo == nil)
        let versioned = PaletteLayout(base: base, style: .none, showsUndo: true, showsVersion: true)
        #expect(versioned.geometry.size.height == base.size.height + 8)
        #expect(versioned.version?.spot == .trailing)
    }

    @Test func endTileSitsAfterTheLayouts() {
        let l = PaletteLayout(base: base, style: .endTile, showsUndo: true, showsVersion: false)
        let tile = base.thumbnails[0].width
        #expect(l.geometry.size.width == base.size.width + tile + PaletteGeometry.spacing)
        #expect(l.undo!.minX > base.thumbnails.last!.maxX)
        #expect(l.isOnUndo(CGPoint(x: l.undo!.midX, y: l.undo!.midY)))
        #expect(!l.isOnUndo(CGPoint(x: base.thumbnails[0].midX, y: base.thumbnails[0].midY)))
    }

    @Test func hiddenUndoLeavesNoTarget() {
        for style in UndoTargetStyle.allCases {
            let l = PaletteLayout(base: base, style: style, showsUndo: false, showsVersion: false)
            #expect(l.undo == nil)
            #expect(!l.isOnUndo(CGPoint(x: 5, y: 5)))
        }
    }

    @Test func leadingTileMovesTheLayoutsRight() {
        let l = PaletteLayout(base: base, style: .leadingTile, showsUndo: true, showsVersion: false)
        #expect(l.undo!.maxX < l.geometry.thumbnails[0].minX)
    }

    @Test func cornerButtonLowersTheShelf() {
        let l = PaletteLayout(base: base, style: .cornerButton, showsUndo: true, showsVersion: false)
        #expect(l.shelf.minY == 14)
        #expect(l.undo!.minY == 0)
        #expect(l.geometry.thumbnails[0].minY == base.thumbnails[0].minY + 14)
        #expect(l.shapes.count == 2)
    }

    @Test func sideBubbleIsOutsideTheShelf() {
        let l = PaletteLayout(base: base, style: .sideBubble, showsUndo: true, showsVersion: true)
        #expect(l.undo!.minX > l.shelf.maxX)
        #expect(l.shapes.count == 3)
        #expect(l.geometry.size.width > l.shelf.width)
    }

    @Test func hangingLipHangsBelow() {
        let l = PaletteLayout(base: base, style: .hangingLip, showsUndo: true, showsVersion: true)
        #expect(l.shapes.first!.rect.maxY > l.shelf.maxY)
        #expect(l.version!.rect.minY > l.shelf.maxY)
    }

    @Test func everyStyleKeepsItsPiecesInTheBox() {
        for style in UndoTargetStyle.allCases {
            let l = PaletteLayout(base: base, style: style, showsUndo: true, showsVersion: true)
            let box = CGRect(origin: .zero, size: l.geometry.size)
            for shape in l.shapes { #expect(box.insetBy(dx: -0.5, dy: -0.5).contains(shape.rect), "\(style)") }
            if let undo = l.undo { #expect(box.insetBy(dx: -0.5, dy: -0.5).contains(undo), "\(style)") }
            for t in l.geometry.thumbnails { #expect(l.shelf.contains(t), "\(style)") }
        }
    }
}
