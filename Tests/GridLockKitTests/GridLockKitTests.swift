import CoreGraphics
import Foundation
import Testing
@testable import GridLockKit

struct DisplayKeyTests {
    private func inputs(builtin: Bool = false, numeric: UInt32 = 0, alnum: String? = nil) -> DisplayKey.Inputs {
        .init(isBuiltin: builtin, vendor: 8718, model: 13428, numericSerial: numeric, alphanumericSerial: alnum, displayUUID: "U")
    }

    @Test func prefersAlphanumericSerial() {
        #expect(DisplayKey.make(inputs(numeric: 16_843_009, alnum: "6CM91601YM")) == "sn:8718-13428-6CM91601YM")
    }

    @Test func skipsPlaceholderNumericSerials() {
        for junk: UInt32 in [0, 1, 0x0101_0101, 0xFFFF_FFFF] {
            #expect(DisplayKey.make(inputs(numeric: junk)) == "uuid:U")
        }
        #expect(DisplayKey.make(inputs(numeric: 810_366_796)) == "edid:8718-13428-810366796")
    }

    @Test func builtinIsBuiltin() {
        #expect(DisplayKey.make(inputs(builtin: true, alnum: "XYZ123")) == "builtin")
    }

    @Test func identicalDisplaysAreKeptApart() {
        let keys = DisplayKey.disambiguate(["uuid:A", "builtin", "uuid:A"], xs: [3000, -1700, 0])
        #expect(keys == ["uuid:A#2", "builtin", "uuid:A"])
    }

    @Test func signatureIgnoresArrangement() {
        #expect(DeskSignature.make(["b", "a"]) == DeskSignature.make(["a", "b"]))
    }
}

struct SettleTrackerTests {
    @Test func switchesOnlyAfterTwoIdenticalSamples() {
        var t = SettleTracker()
        #expect(t.sample("a") == nil)
        #expect(t.sample("a") == .settled(signature: "a", changed: true, disrupted: true))
        // Docking passes through partial sets; none of them settle.
        #expect(t.sample("a|b") == nil)
        #expect(t.sample("a|b|c") == nil)
        #expect(t.sample("a|b|c") == .settled(signature: "a|b|c", changed: true, disrupted: true))
    }
}

struct GridMathTests {
    let grid = GridSpec(columns: 6, rows: 4)
    let visible = CGRect(x: 0, y: 30, width: 1200, height: 800)

    @Test func cellsToFrameAndBack() {
        let cells = CellRange(column: 1, row: 1, columns: 3, rows: 2)
        let frame = GridMath.frame(for: cells, grid: grid, visible: visible)
        #expect(frame == CGRect(x: 200, y: 230, width: 600, height: 400))
        #expect(GridMath.cells(for: frame, grid: grid, visible: visible) == cells)
    }

    @Test func framesRoundToNearestLines() {
        // A window a little off the lines still reads as the cells it nearly fills.
        let frame = CGRect(x: 190, y: 245, width: 620, height: 380)
        #expect(GridMath.cells(for: frame, grid: grid, visible: visible) == CellRange(column: 1, row: 1, columns: 3, rows: 2))
    }

    @Test func tinyWindowGetsOneCell() {
        let frame = CGRect(x: 420, y: 250, width: 40, height: 30)
        #expect(GridMath.cells(for: frame, grid: grid, visible: visible) == CellRange(column: 2, row: 1, columns: 1, rows: 1))
    }

    @Test func gapAndMarginStayInside() {
        let spaced = GridSpec(columns: 2, rows: 1, gap: 10, margin: 20)
        let left = GridMath.frame(for: CellRange(column: 0, row: 0, columns: 1, rows: 1), grid: spaced, visible: visible)
        let right = GridMath.frame(for: CellRange(column: 1, row: 0, columns: 1, rows: 1), grid: spaced, visible: visible)
        #expect(left == CGRect(x: 20, y: 50, width: 575, height: 760))
        #expect(right.minX - left.maxX == 10)
        #expect(right.maxX == visible.maxX - 20)
    }

    @Test func displayAboveAndLeftOfMain() {
        // Negative global coordinates, as for a display arranged above-left of the main one.
        let above = CGRect(x: -1920, y: -1080, width: 1920, height: 1080)
        let frame = GridMath.frame(for: CellRange(column: 0, row: 0, columns: 3, rows: 2), grid: grid, visible: above)
        #expect(frame == CGRect(x: -1920, y: -1080, width: 960, height: 540))
        #expect(GridMath.cells(for: frame, grid: grid, visible: above) == CellRange(column: 0, row: 0, columns: 3, rows: 2))
    }

    @Test func flipBetweenAppKitAndAccessibility() {
        let appKit = CGRect(x: 0, y: 100, width: 300, height: 200)
        let flipped = ScreenSpace.flip(appKit, mainHeight: 1000)
        #expect(flipped == CGRect(x: 0, y: 700, width: 300, height: 200))
        #expect(ScreenSpace.flip(flipped, mainHeight: 1000) == appKit)
    }

    @Test func cellUnderPoint() {
        #expect(GridMath.cell(at: CGPoint(x: 1199, y: 829), grid: grid, visible: visible)! == (5, 3))
        #expect(GridMath.cell(at: CGPoint(x: 10, y: 10), grid: grid, visible: visible) == nil)
    }
}

struct CellRangeTests {
    let grid = GridSpec(columns: 6, rows: 4)

    @Test func dragEitherWay() {
        #expect(CellRange(from: (4, 3), to: (1, 0)) == CellRange(column: 1, row: 0, columns: 4, rows: 4))
    }

    @Test func movesStopAtEdges() {
        let r = CellRange(column: 4, row: 0, columns: 2, rows: 1)
        #expect(r.moved(dx: 1, dy: -1, in: grid) == r)
        #expect(r.moved(dx: -1, dy: 1, in: grid) == CellRange(column: 3, row: 1, columns: 2, rows: 1))
    }

    @Test func resizeNeverBelowOneCellOrPastGrid() {
        let one = CellRange(column: 2, row: 2, columns: 1, rows: 1)
        #expect(one.resized(.right, by: -1, in: grid) == one)
        #expect(one.resized(.left, by: -1, in: grid) == one)
        #expect(one.resized(.right, by: 10, in: grid).columns == 4)
        #expect(one.resized(.left, by: 10, in: grid) == CellRange(column: 0, row: 2, columns: 3, rows: 1))
        #expect(one.resized(.top, by: 1, in: grid) == CellRange(column: 2, row: 1, columns: 1, rows: 2))
    }

    @Test func mapsBetweenGrids() {
        let r = CellRange(column: 3, row: 0, columns: 3, rows: 4)
        #expect(r.mapped(from: grid, to: GridSpec(columns: 12, rows: 4)) == CellRange(column: 6, row: 0, columns: 6, rows: 4))
    }

    @Test func describesFromOne() {
        #expect(CellRange(column: 0, row: 0, columns: 4, rows: 3).description == "columns 1–4, rows 1–3")
        #expect(CellRange(column: 2, row: 1, columns: 1, rows: 1).description == "column 3, row 2")
    }
}

struct LayoutTests {
    @Test func familiesProduceTheirZones() {
        #expect(LayoutKind.columns(count: 3).zones().count == 3)
        #expect(LayoutKind.grid(columns: 3, rows: 2).zones().count == 6)
        let split = LayoutKind.split(lead: 2, parts: 3).zones()
        #expect(split.count == 2)
        #expect(abs(split[0].width - 2.0 / 3) < 1e-9)
        #expect(abs(LayoutKind.split(lead: 1, parts: 3).zones()[0].width - 1.0 / 3) < 1e-9)
        #expect(LayoutKind.maximize.zones() == [.full])
    }

    @Test func customLayoutsResolve() {
        let custom = CustomLayout(name: "Wide left", zones: [UnitRect(x: 0, y: 0, width: 0.7, height: 1)])
        #expect(LayoutKind.custom(id: custom.id).zones(custom: [custom]) == custom.zones)
        #expect(LayoutKind.custom(id: UUID()).zones(custom: [custom]).isEmpty)
        #expect(LayoutKind.custom(id: custom.id).title(custom: [custom]) == "Wide left")
    }

    @Test func tinyZonesAreRefused() {
        #expect(!UnitRect(x: 0, y: 0, width: 0.04, height: 1).isUsable)
        #expect(UnitRect(x: 0.5, y: 0, width: 0.5, height: 1).isUsable)
    }

    @Test func titles() {
        #expect(LayoutKind.columns(count: 2).title() == "Halves")
        #expect(LayoutKind.columns(count: 3).title() == "Columns × 3")
        #expect(LayoutKind.grid(columns: 3, rows: 2).title() == "Grid 3 × 2")
    }
}

struct DeskTests {
    private func display(_ key: String, _ w: CGFloat = 2560, _ h: CGFloat = 1440, x: CGFloat = 0) -> LiveDisplay {
        LiveDisplay(key: key, name: key, isBuiltin: key == "builtin", isMain: false,
                    bounds: CGRect(x: x, y: 0, width: w, height: h), visible: CGRect(x: x, y: 0, width: w, height: h))
    }

    private func desk(_ displays: [LiveDisplay], columns: Int, used: Date) -> Desk {
        Desk(name: "D", signature: DeskSignature.make(displays.map(\.key)), displays: displays.map(\.record),
             settings: Dictionary(uniqueKeysWithValues: displays.map {
                 ($0.key, DisplaySettings(grid: GridSpec(columns: columns, rows: 4), palette: []))
             }), lastUsed: used)
    }

    @Test func settingsAreKeptPerDesk() {
        var library = DeskLibrary(machineID: "m", machineName: "Mac")
        let dell = display("dell")
        library.desks = [desk([dell], columns: 6, used: .distantPast), desk([dell, display("builtin", x: -1700)], columns: 8, used: .now)]
        library.desks[0].settings["dell"]!.grid.columns = 10
        #expect(library.desks[1].settings["dell"]!.grid.columns == 8)
    }

    @Test func newDeskBorrowsSameDisplayFromMostRecentDesk() {
        var library = DeskLibrary(machineID: "m", machineName: "Mac")
        let dell = display("dell")
        library.desks = [desk([dell], columns: 6, used: .distantPast), desk([dell], columns: 9, used: .now)]
        let seeded = library.seededSettings(for: [dell, display("hp", 1920, 1080)])
        #expect(seeded["dell"]!.grid.columns == 9)
        // Nothing known about the HP: suggestions for a 16:9 display.
        #expect(seeded["hp"]!.grid == GridSpec(columns: 6, rows: 4))
    }

    @Test func newDeskBorrowsDisplayOfSameSize() {
        var library = DeskLibrary(machineID: "m", machineName: "Mac")
        library.desks = [desk([display("a", 3440, 1440)], columns: 12, used: .now)]
        #expect(library.seededSettings(for: [display("b", 3440, 1440)])["b"]!.grid.columns == 12)
    }

    @Test func suggestedGridsFollowShape() {
        #expect(GridSpec.suggested(for: CGSize(width: 3440, height: 1440)).columns == 8)
        #expect(GridSpec.suggested(for: CGSize(width: 1440, height: 2560)) == GridSpec(columns: 3, rows: 6))
    }

    @Test func libraryRoundTripsAndToleratesMissingFields() throws {
        var library = DeskLibrary(machineID: "m", machineName: "Mac")
        // Whole seconds: ISO 8601 keeps no fractions, which is fine for "last used".
        let second = Date(timeIntervalSince1970: 1_800_000_000)
        var d = desk([display("dell")], columns: 6, used: second)
        d.created = second
        library.desks = [d]
        library.customLayouts = [CustomLayout(name: "C", zones: [.full])]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(DeskLibrary.self, from: encoder.encode(library))
        #expect(back.desks == library.desks)
        #expect(back.customLayouts == library.customLayouts)
        let old = try decoder.decode(DeskLibrary.self, from: Data(#"{"machineID":"m","machineName":"Mac","desks":[],"future":1}"#.utf8))
        #expect(old.customLayouts.isEmpty)
    }

    @Test func displayHoldingMostOfAWindow() {
        let left = display("l", 1000, 1000), right = display("r", 1000, 1000, x: 1000)
        #expect(LiveDisplay.index(holding: CGRect(x: 600, y: 0, width: 500, height: 500), in: [left, right]) == 0)
        #expect(LiveDisplay.index(holding: CGRect(x: 800, y: 0, width: 500, height: 500), in: [left, right]) == 1)
        #expect(LiveDisplay.index(holding: CGRect(x: 5000, y: 0, width: 10, height: 10), in: [left, right]) == 1)
    }
}

struct MoveHistoryTests {
    @Test func keepsTheLastTenAndSkipsClosedWindows() {
        var h = MoveHistory<Int>()
        for i in 1...12 { h.push(i) }
        #expect(h.items.first == 3)
        #expect(h.popLast { $0 != 12 } == 11)
        #expect(h.items.last == 10)
    }
}

struct URLActionTests {
    private func action(_ string: String) -> URLAction? { URLAction(URL(string: string)!) }

    @Test func readsEachAction() {
        #expect(action("gridlock://grid") == .grid)
        #expect(action("gridlock://undo") == .undo)
        #expect(action("gridlock://palette?source=toolhud") == .palette)
        #expect(action("gridlock://settings") == .settings)
        #expect(action("gridlock://") == .settings)
        #expect(action("windowkeeper://grid") == nil)
    }

    @Test func snapTakesTheZoneFromTheQueryOrTheHost() {
        for zone in ["left-half", "right-half", "maximize", "center"] {
            #expect(action("gridlock://snap?zone=\(zone)") == .snap(zone: zone))
            // ToolHUD's form, with the marker it adds.
            #expect(action("gridlock://snap-\(zone)?source=toolhud") == .snap(zone: zone))
        }
        #expect(action("gridlock://snap") == .snap(zone: nil))
    }
}
