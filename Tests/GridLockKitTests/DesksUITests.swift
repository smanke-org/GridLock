import CoreGraphics
import Foundation
import Testing
@testable import GridLockKit

private func display(_ key: String, _ w: CGFloat = 2560, _ h: CGFloat = 1440, x: CGFloat = 0, y: CGFloat = 0) -> LiveDisplay {
    LiveDisplay(key: key, name: key, isBuiltin: key == "builtin", isMain: false,
                bounds: CGRect(x: x, y: y, width: w, height: h), visible: CGRect(x: x, y: y, width: w, height: h))
}

private func desk(_ name: String, _ displays: [LiveDisplay], columns: Int = 6, used: Date = .now) -> Desk {
    Desk(name: name, signature: DeskSignature.make(displays.map(\.key)), displays: displays.map(\.record),
         settings: Dictionary(uniqueKeysWithValues: displays.map {
             ($0.key, DisplaySettings(grid: GridSpec(columns: columns, rows: 4), palette: Palette.suggested(for: GridSpec(columns: columns, rows: 4))))
         }), lastUsed: used)
}

/// S-006, S-020: a display's grid and palette belong to it at one desk.
struct DeskEditingTests {
    @Test func editingADisplayAtOneDeskLeavesOtherDesksAlone() {
        let dell = display("dell")
        var library = DeskLibrary(machineID: "m", machineName: "Mac")
        library.desks = [desk("Home", [dell]), desk("Office", [dell, display("builtin", x: -1700)])]
        let home = library.desks[0].id
        #expect(library.updateSettings(desk: home, display: "dell") {
            $0.grid.columns = 10
            $0.grid.gap = 8
            $0.palette = [PaletteEntry(kind: .maximize)]
        })
        #expect(library.desks[0].settings["dell"]!.grid.columns == 10)
        #expect(library.desks[1].settings["dell"]!.grid.columns == 6)
        #expect(library.desks[1].settings["dell"]!.grid.gap == 0)
        #expect(library.desks[1].settings["dell"]!.palette.count > 1)
    }

    @Test func editsAreClampedAndNoChangeReportsFalse() {
        var library = DeskLibrary(machineID: "m", machineName: "Mac")
        library.desks = [desk("Home", [display("dell")])]
        let id = library.desks[0].id
        library.updateSettings(desk: id, display: "dell") { $0.grid.columns = 99 }
        #expect(library.desks[0].settings["dell"]!.grid.columns == GridSpec.columnRange.upperBound)
        #expect(!library.updateSettings(desk: id, display: "dell") { _ in })
        #expect(!library.updateSettings(desk: UUID(), display: "dell") { $0.grid.rows = 2 })
    }

    @Test func pasteReplacesGridAndPaletteOnly() {
        let source = DisplaySettings(grid: GridSpec(columns: 8, rows: 3, gap: 6, margin: 12),
                                     palette: [PaletteEntry(kind: .columns(count: 3)), PaletteEntry(kind: .maximize)])
        let target = DisplaySettings(grid: GridSpec(columns: 4, rows: 4), palette: [PaletteEntry(kind: .rows(count: 2))])
        let pasted = target.pasting(source)
        #expect(pasted.grid == source.grid)
        #expect(pasted.palette.map(\.kind) == source.palette.map(\.kind))
        // Fresh entry ids, so the two palettes don't share them.
        #expect(Set(pasted.palette.map(\.id)).isDisjoint(with: source.palette.map(\.id)))
    }

    @Test func deskListPutsCurrentFirstThenMostRecent() {
        var library = DeskLibrary(machineID: "m", machineName: "Mac")
        library.desks = [desk("Old", [display("a")], used: .distantPast), desk("Here", [display("b")], used: .distantPast),
                         desk("Recent", [display("c")], used: .now)]
        let here = library.desks[1].id
        #expect(library.listed(current: here).map(\.name) == ["Here", "Recent", "Old"])
        #expect(!library.canDelete(here, current: here))
        #expect(library.canDelete(library.desks[0].id, current: here))
    }

    @Test func newDeskTakesWindowKeepersNameForTheSameSignature() {
        var library = DeskLibrary(machineID: "m", machineName: "Mac")
        let displays = [display("builtin", 1512, 982, x: -1512), display("sn:1-2-ABCD")]
        let names = [DeskSignature.make(displays.map(\.key)): "Main office desk"]
        #expect(library.newDesk(for: displays, knownNames: names).name == "Main office desk")
        #expect(library.newDesk(for: displays).name == "Built-in + sn:1-2-ABCD")
        library.desks = [desk("Main office desk", [display("x")])]
        #expect(library.newDesk(for: displays, knownNames: names).name == "Main office desk (2)")
    }

    @Test func newDeskIsSeededFromTheSameDisplayElsewhere() {
        var library = DeskLibrary(machineID: "m", machineName: "Mac")
        let dell = display("dell")
        library.desks = [desk("Old", [dell], columns: 5, used: .distantPast), desk("Recent", [dell], columns: 9, used: .now)]
        let new = library.newDesk(for: [dell, display("builtin", 1512, 982, x: -1512)])
        #expect(new.settings["dell"]!.grid.columns == 9)
        #expect(new.settings["builtin"] != nil)
    }
}

struct WindowKeeperNamesTests {
    @Test func readsNamesBySignatureAndSkipsBlankOnes() {
        let json = #"""
        {"formatVersion":1,"profiles":[
          {"name":"Main office desk","signature":"builtin|sn:1-2-A","windows":[],"isLocked":false},
          {"name":"  ","signature":"uuid:X"},
          {"name":"Second","signature":"builtin|sn:1-2-A"},
          {"signature":"edid:1"}
        ]}
        """#
        let names = WindowKeeperNames.parse(Data(json.utf8))
        #expect(names == ["builtin|sn:1-2-A": "Main office desk"])
        #expect(WindowKeeperNames.parse(Data("not json".utf8)).isEmpty)
    }
}

struct DeskPictureTests {
    @Test func keepsArrangementAndProportions() {
        // A 16:10 laptop left of a 4K display, bottoms not aligned.
        let frames = [CGRect(x: -1512, y: 400, width: 1512, height: 982), CGRect(x: 0, y: 0, width: 3840, height: 2160)]
        let fitted = DeskPicture.fit(frames, in: CGSize(width: 400, height: 200), inset: 10)
        #expect(fitted.count == 2)
        #expect(fitted[0].maxX <= fitted[1].minX + 0.001)
        #expect(abs(fitted[0].width / fitted[0].height - 1512.0 / 982) < 0.001)
        #expect(abs(fitted[1].width / fitted[1].height - 3840.0 / 2160) < 0.001)
        for f in fitted { #expect(f.minX >= 9.999 && f.maxX <= 390.001 && f.minY >= 9.999 && f.maxY <= 190.001) }
        #expect(DeskPicture.fit([], in: CGSize(width: 10, height: 10)).isEmpty)
    }
}

/// S-021: counts per family.
struct PaletteEditingTests {
    @Test func countsStayInTheirRanges() {
        #expect(LayoutKind.columns(count: 3).withCount(9) == .columns(count: 6))
        #expect(LayoutKind.rows(count: 3).withCount(1) == .rows(count: 2))
        #expect(LayoutKind.maximize.withCount(4) == .maximize)
        #expect(LayoutKind.grid(columns: 2, rows: 2).withGrid(columns: 3, rows: 2) == .grid(columns: 3, rows: 2))
        // A 1 × 1 grid would be Maximize: refused.
        #expect(LayoutKind.grid(columns: 2, rows: 1).withGrid(columns: 1, rows: 1) == .grid(columns: 2, rows: 1))
    }

    @Test func countsMakeTheRightZones() {
        #expect(LayoutKind.columns(count: 2).withCount(3).zones().count == 3)
        #expect(LayoutKind.columns(count: 3).zones().allSatisfy { abs($0.width - 1.0 / 3) < 1e-9 })
        #expect(LayoutKind.grid(columns: 1, rows: 2).withGrid(columns: 3, rows: 2).zones().count == 6)
        for split in LayoutKind.splits { #expect(split.zones().count == 2) }
        #expect(abs(LayoutKind.split(lead: 3, parts: 4).zones()[0].width - 0.75) < 1e-9)
    }

    @Test func addingAFamilyPicksACountNotYetShown() {
        let palette = [PaletteEntry(kind: .columns(count: 2)), PaletteEntry(kind: .columns(count: 3))]
        #expect(Palette.adding(.columns, to: palette) == .columns(count: 4))
        #expect(Palette.adding(.rows, to: palette) == .rows(count: 2))
        #expect(Palette.adding(.split, to: [PaletteEntry(kind: .split(lead: 2, parts: 3))]) == .split(lead: 1, parts: 3))
        #expect(Palette.adding(.maximize, to: [PaletteEntry(kind: .maximize)]) == .maximize)
    }

    @Test func sameFamilyTwiceWithDifferentCounts() {
        let entries = [PaletteEntry(kind: .columns(count: 2)), PaletteEntry(kind: .columns(count: 4))]
        #expect(Set(entries.compactMap(\.kind.family)) == [.columns])
        #expect(entries.map { $0.kind.title() } == ["Halves", "Columns × 4"])
    }

    @Test func movingReordersLikeOnMove() {
        let entries = [LayoutKind.maximize, .columns(count: 2), .rows(count: 2)].map { PaletteEntry(kind: $0) }
        #expect(Palette.moving(entries, from: [0], to: 3).map(\.kind) == [.columns(count: 2), .rows(count: 2), .maximize])
        #expect(Palette.moving(entries, from: [2], to: 0).map(\.kind) == [.rows(count: 2), .maximize, .columns(count: 2)])
    }
}

/// S-025: the layout editor's geometry.
struct LayoutCanvasTests {
    @Test func dragsDrawSnappedFractionalZones() {
        let zone = LayoutCanvas.zone(from: CGPoint(x: 0.51, y: 0.98), to: CGPoint(x: 0.02, y: 0.01))
        #expect(zone == UnitRect(x: 0, y: 0, width: 0.5, height: 1))
        // Fractions: the same layout fits any display shape.
        let wide = GridMath.frame(for: zone!, visible: CGRect(x: 0, y: 0, width: 3440, height: 1440), gap: 0, margin: 0)
        let tall = GridMath.frame(for: zone!, visible: CGRect(x: 0, y: 0, width: 1440, height: 2560), gap: 0, margin: 0)
        #expect(wide == CGRect(x: 0, y: 0, width: 1720, height: 1440))
        #expect(tall == CGRect(x: 0, y: 0, width: 720, height: 2560))
    }

    @Test func zonesUnderFivePercentAreRefused() {
        // Without snapping, a 4% sliver is too small; 6% is fine.
        #expect(LayoutCanvas.zone(from: CGPoint(x: 0.2, y: 0), to: CGPoint(x: 0.24, y: 1), divisions: nil) == nil)
        #expect(LayoutCanvas.zone(from: CGPoint(x: 0.2, y: 0), to: CGPoint(x: 0.26, y: 1), divisions: nil) != nil)
        // A click (no drag) draws nothing.
        #expect(LayoutCanvas.zone(from: CGPoint(x: 0.3, y: 0.3), to: CGPoint(x: 0.31, y: 0.31)) == nil)
        let zone = UnitRect(x: 0, y: 0, width: 0.5, height: 1)
        #expect(LayoutCanvas.adjusted(zone, .right, dx: -0.49, dy: 0, divisions: nil) == nil)
        #expect(!CustomLayout(name: "Sliver", zones: [UnitRect(x: 0, y: 0, width: 0.03, height: 1)]).isValid)
    }

    @Test func overlappingZonesAreAllowed() {
        let layout = CustomLayout(name: "Overlap", zones: [UnitRect(x: 0, y: 0, width: 0.6, height: 1),
                                                           UnitRect(x: 0.4, y: 0, width: 0.6, height: 1)])
        #expect(layout.isValid)
        #expect(LayoutCanvas.zoneIndex(at: CGPoint(x: 0.5, y: 0.5), in: layout.zones) == 1)
        #expect(LayoutCanvas.zoneIndex(at: CGPoint(x: 0.1, y: 0.5), in: layout.zones) == 0)
    }

    @Test func edgesAndMovesSnapAndStayOnTheCanvas() {
        let zone = UnitRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        #expect(LayoutCanvas.adjusted(zone, .left, dx: -0.24, dy: 0) == UnitRect(x: 0, y: 0.25, width: 0.75, height: 0.5))
        #expect(LayoutCanvas.adjusted(zone, .body, dx: 0.9, dy: -0.9) == UnitRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
        #expect(!CustomLayout(name: " ", zones: [zone]).isValid)
        #expect(!CustomLayout(name: "Empty", zones: []).isValid)
    }

    @Test func deletingACustomLayoutTakesItOutOfEveryPalette() {
        var library = DeskLibrary(machineID: "m", machineName: "Mac")
        let layout = CustomLayout(name: "Focus", zones: [.full])
        library.saveCustomLayout(layout)
        library.desks = [desk("Home", [display("a")]), desk("Office", [display("a"), display("b", x: 2560)])]
        library.updateSettings(desk: library.desks[0].id, display: "a") { $0.palette.append(PaletteEntry(kind: .custom(id: layout.id))) }
        library.updateSettings(desk: library.desks[1].id, display: "b") { $0.palette.append(PaletteEntry(kind: .custom(id: layout.id))) }
        #expect(library.paletteCount(using: layout.id) == 2)
        var renamed = layout
        renamed.name = "Focus Wide"
        library.saveCustomLayout(renamed)
        #expect(library.customLayouts.map(\.name) == ["Focus Wide"])
        library.removeCustomLayout(layout.id)
        #expect(library.customLayouts.isEmpty)
        #expect(library.paletteCount(using: layout.id) == 0)
        #expect(library.desks[1].settings["a"]!.palette.count == Palette.suggested(for: GridSpec(columns: 6, rows: 4)).count)
    }
}
