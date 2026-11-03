import CoreGraphics
import Foundation
import Testing
@testable import GridLockKit

private func display(_ key: String, _ w: CGFloat = 2560, _ h: CGFloat = 1440) -> LiveDisplay {
    LiveDisplay(key: key, name: key, isBuiltin: key == "builtin", isMain: false,
                bounds: CGRect(x: 0, y: 0, width: w, height: h), visible: CGRect(x: 0, y: 30, width: w, height: h - 30))
}

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

/// A Mac's library with one desk of the given displays.
private func mac(_ id: String, shares: Bool = true, displays: [String] = ["builtin", "sn:LG"]) -> DeskLibrary {
    var library = DeskLibrary(machineID: id, machineName: id, shares: shares)
    library.desks.append(library.newDesk(for: displays.map { display($0) }, now: t0))
    return library
}

@Suite struct DeskSyncTests {
    @Test func editsAreStampedOnlyWhenSomethingChanges() {
        var a = mac("A")
        let desk = a.desks[0].id
        #expect(a.desks[0].settings["sn:LG"]?.modified == nil)
        #expect(!a.updateSettings(desk: desk, display: "sn:LG", now: t0) { _ in })
        #expect(a.updateSettings(desk: desk, display: "sn:LG", now: t0.addingTimeInterval(5.7)) { $0.grid.columns = 8 })
        #expect(a.desks[0].settings["sn:LG"]?.modified == t0.addingTimeInterval(5))
    }

    @Test func theNewestChangeAtTheSameDeskWins() {
        var a = mac("A"), b = mac("B")
        a.updateSettings(desk: a.desks[0].id, display: "sn:LG", now: t0.addingTimeInterval(10)) { $0.grid.columns = 8 }
        b.updateSettings(desk: b.desks[0].id, display: "sn:LG", now: t0.addingTimeInterval(20)) { $0.grid.columns = 12 }
        #expect(DeskSync.merge(a, with: [b]).desks[0].settings["sn:LG"]?.grid.columns == 12)
        #expect(DeskSync.merge(b, with: [a]).desks[0].settings["sn:LG"]?.grid.columns == 12)
        // Untouched displays stay as they are.
        #expect(DeskSync.merge(a, with: [b]).desks[0].settings["builtin"] == a.desks[0].settings["builtin"])
    }

    @Test func otherDesksAndNonSharingMacsAreLeftAlone() {
        let a = mac("A")
        var other = mac("B", displays: ["sn:LG"])          // a Mac mini at the same monitor
        other.updateSettings(desk: other.desks[0].id, display: "sn:LG", now: t0.addingTimeInterval(30)) { $0.grid.columns = 3 }
        #expect(DeskSync.merge(a, with: [other]).desks[0].settings["sn:LG"]?.grid.columns != 3)
        var private_ = mac("C", shares: false)
        private_.updateSettings(desk: private_.desks[0].id, display: "sn:LG", now: t0.addingTimeInterval(30)) { $0.grid.columns = 3 }
        #expect(DeskSync.merge(a, with: [private_]).desks[0].settings["sn:LG"]?.grid.columns != 3)
    }

    @Test func mergingBackAndForthSettles() {
        var a = mac("A"), b = mac("B")
        a.updateSettings(desk: a.desks[0].id, display: "sn:LG", now: t0.addingTimeInterval(10)) { $0.grid.gap = 8 }
        b.saveCustomLayout(CustomLayout(name: "Wide Center", zones: [UnitRect(x: 0.1, y: 0, width: 0.8, height: 1)]),
                           now: t0.addingTimeInterval(11))
        let a1 = DeskSync.merge(a, with: [b])
        let b1 = DeskSync.merge(b, with: [a1])
        #expect(DeskSync.merge(a1, with: [b1]).desks == a1.desks)
        #expect(DeskSync.merge(a1, with: [b1]).customLayouts == a1.customLayouts)
        #expect(b1.desks[0].settings["sn:LG"] == a1.desks[0].settings["sn:LG"])
    }

    @Test func customLayoutsTravelAndDeletionsFollow() {
        var a = mac("A"), b = mac("B")
        let layout = CustomLayout(name: "Wide Center", zones: [UnitRect(x: 0.1, y: 0, width: 0.8, height: 1)])
        b.saveCustomLayout(layout, now: t0.addingTimeInterval(10))
        a = DeskSync.merge(a, with: [b])
        #expect(a.customLayouts.map(\.name) == ["Wide Center"])

        // A renames it later: B takes the rename.
        var renamed = a.customLayouts[0]
        renamed.name = "Middle"
        a.saveCustomLayout(renamed, now: t0.addingTimeInterval(20))
        #expect(DeskSync.merge(b, with: [a]).customLayouts.map(\.name) == ["Middle"])

        // B puts it in a palette, then A deletes it: gone from B's list and B's palette.
        b.updateSettings(desk: b.desks[0].id, display: "sn:LG", now: t0.addingTimeInterval(25)) {
            $0.palette.append(PaletteEntry(kind: .custom(id: layout.id)))
        }
        a.removeCustomLayout(layout.id, now: t0.addingTimeInterval(30))
        let b2 = DeskSync.merge(b, with: [a])
        #expect(b2.customLayouts.isEmpty)
        #expect(!(b2.desks[0].settings["sn:LG"]?.palette.contains { $0.kind == .custom(id: layout.id) } ?? true))
        // And it doesn't come back to A from B's older copy.
        #expect(DeskSync.merge(a, with: [b]).customLayouts.isEmpty)
    }

    @Test func aDeskNewHereStartsFromTheSameDeskElsewhere() {
        var b = mac("B")
        b.desks[0].name = "Studio"
        b.updateSettings(desk: b.desks[0].id, display: "sn:LG", now: t0.addingTimeInterval(10)) { $0.grid.columns = 9 }
        let a = DeskLibrary(machineID: "A", machineName: "A", shares: true)
        let desk = a.newDesk(for: [display("builtin"), display("sn:LG")], others: [b], now: t0.addingTimeInterval(60))
        #expect(desk.name == "Studio")
        #expect(desk.settings["sn:LG"]?.grid.columns == 9)
        // Kept as it was, change date and all, so it doesn't look like a new change.
        #expect(desk.settings["sn:LG"]?.modified == b.desks[0].settings["sn:LG"]?.modified)
        // WindowKeeper's name still comes first.
        let named = a.newDesk(for: [display("builtin"), display("sn:LG")], knownNames: [b.desks[0].signature: "Home Office"], others: [b])
        #expect(named.name == "Home Office")
    }

    @Test func olderFilesWithoutTheNewFieldsStillRead() throws {
        let json = #"{"formatVersion":1,"machineID":"X","machineName":"X","desks":[],"customLayouts":[{"id":"8C1C0F6E-6B0E-4E43-9C55-2E5B1D3E5A10","name":"Old","zones":[]}]}"#
        let library = try JSONDecoder().decode(DeskLibrary.self, from: Data(json.utf8))
        #expect(!library.shares)
        #expect(library.deletedLayouts.isEmpty)
        #expect(library.customLayouts.first?.modified == nil)
    }
}
