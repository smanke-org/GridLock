import CoreGraphics
import Foundation

/// Everything GridLock keeps for one display at one desk: its grid and its palette. The
/// same display can be set up differently at each desk it's used at.
public struct DisplaySettings: Codable, Hashable, Sendable {
    public var grid: GridSpec
    public var palette: [PaletteEntry]
    /// When the user last changed them, for settings sync: the newest change wins on every
    /// Mac at the same desk. Nil for settings GridLock chose and nobody has touched.
    public var modified: Date?

    public init(grid: GridSpec, palette: [PaletteEntry], modified: Date? = nil) {
        self.grid = grid
        self.palette = palette
        self.modified = modified
    }

    /// The same grid and palette, whenever they were set.
    public func sameContent(as other: DisplaySettings) -> Bool {
        grid == other.grid && palette == other.palette
    }

    public static func suggested(for size: CGSize) -> DisplaySettings {
        let grid = GridSpec.suggested(for: size)
        return DisplaySettings(grid: grid, palette: Palette.suggested(for: grid))
    }

    /// A copy whose palette entries have fresh ids, so pasting one display's settings onto
    /// another doesn't leave two palettes sharing entry ids.
    public var copied: DisplaySettings {
        DisplaySettings(grid: grid, palette: palette.map { PaletteEntry(kind: $0.kind) })
    }
}

/// One set of connected displays, recognized by their keys.
public struct Desk: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// The sorted display keys. See `DeskSignature`.
    public var signature: String
    public var displays: [DisplayRecord]
    /// Per display key.
    public var settings: [String: DisplaySettings]
    public var created: Date
    public var lastUsed: Date

    public init(id: UUID = UUID(), name: String, signature: String, displays: [DisplayRecord],
                settings: [String: DisplaySettings], created: Date = Date(), lastUsed: Date = Date()) {
        self.id = id
        self.name = name
        self.signature = signature
        self.displays = displays
        self.settings = settings
        self.created = created
        self.lastUsed = lastUsed
    }
}

/// Everything one Mac keeps. One per Mac, in that Mac's own iCloud folder.
public struct DeskLibrary: Codable, Sendable {
    public var formatVersion: Int
    public var machineID: String
    public var machineName: String
    public var desks: [Desk]
    public var customLayouts: [CustomLayout]
    /// Custom layouts deleted here, by id, with when: another Mac still holding one takes
    /// the deletion rather than bringing it back.
    public var deletedLayouts: [String: Date]
    /// Whether this Mac shares its grids, palettes and custom layouts with the user's other
    /// Macs ("Sync settings with your other Macs"). Other Macs ignore a library that doesn't.
    public var shares: Bool

    public init(machineID: String, machineName: String, desks: [Desk] = [], customLayouts: [CustomLayout] = [],
                deletedLayouts: [String: Date] = [:], shares: Bool = false) {
        formatVersion = 1
        self.machineID = machineID
        self.machineName = machineName
        self.desks = desks
        self.customLayouts = customLayouts
        self.deletedLayouts = deletedLayouts
        self.shares = shares
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, machineID, machineName, desks, customLayouts, deletedLayouts, shares
    }

    /// Lenient about fields a later version adds or an earlier one lacked.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try c.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        machineID = try c.decodeIfPresent(String.self, forKey: .machineID) ?? ""
        machineName = try c.decodeIfPresent(String.self, forKey: .machineName) ?? ""
        desks = try c.decodeIfPresent([Desk].self, forKey: .desks) ?? []
        customLayouts = try c.decodeIfPresent([CustomLayout].self, forKey: .customLayouts) ?? []
        deletedLayouts = try c.decodeIfPresent([String: Date].self, forKey: .deletedLayouts) ?? [:]
        shares = try c.decodeIfPresent(Bool.self, forKey: .shares) ?? false
    }

    public func desk(withSignature signature: String) -> Desk? {
        desks.first { $0.signature == signature }
    }

    /// "Base", or "Base (2)" and up when a desk already has that name.
    public func uniqueName(_ base: String) -> String {
        let taken = Set(desks.map(\.name))
        guard taken.contains(base) else { return base }
        var n = 2
        while taken.contains("\(base) (\(n))") { n += 1 }
        return "\(base) (\(n))"
    }

    /// Settings for each display of a desk seen for the first time, borrowed from the most
    /// similar desk already known: the same desk on another Mac that shares (`others`)
    /// first, as it is; else the same display at the most recently used desk here or on
    /// another Mac; else a display of the same size; else what suits the display's shape.
    public func seededSettings(for displays: [LiveDisplay], others: [DeskLibrary] = []) -> [String: DisplaySettings] {
        let shared = others.filter { $0.shares && $0.machineID != machineID }
        let signature = DeskSignature.make(displays.map(\.key))
        let twins = shared.compactMap { $0.desk(withSignature: signature) }
        let recent = (desks + shared.flatMap(\.desks)).sorted { $0.lastUsed > $1.lastUsed }
        var result: [String: DisplaySettings] = [:]
        for display in displays {
            let fromTwin = twins.compactMap { $0.settings[display.key] }
                .max { ($0.modified ?? .distantPast) < ($1.modified ?? .distantPast) }
            if let fromTwin {
                result[display.key] = fromTwin
                continue
            }
            if let same = recent.lazy.compactMap({ $0.settings[display.key] }).first {
                result[display.key] = same.copied
                continue
            }
            let size = display.bounds.size
            let sameSize = recent.lazy.compactMap { desk in
                desk.displays.first { $0.bounds.width == size.width && $0.bounds.height == size.height }
                    .flatMap { desk.settings[$0.key] }
            }.first
            result[display.key] = sameSize?.copied ?? .suggested(for: size)
        }
        return result
    }

    /// A display's settings at a desk, falling back to suggestions for one the desk doesn't
    /// know yet.
    public func settings(forDisplay key: String, size: CGSize, atDesk id: UUID?) -> DisplaySettings {
        desks.first { $0.id == id }?.settings[key] ?? .suggested(for: size)
    }
}
