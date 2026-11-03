import CoreGraphics
import Foundation

extension DisplaySettings {
    /// Pasting another display's settings: its grid (columns, rows, gap, margin) and its
    /// palette replace these; anything else a display keeps stays.
    public func pasting(_ clip: DisplaySettings) -> DisplaySettings {
        var result = self
        result.grid = clip.grid.clamped
        result.palette = clip.copied.palette
        return result
    }
}

extension DeskLibrary {
    /// Changes one display's settings at one desk and nowhere else. A display the desk
    /// doesn't have settings for yet starts from the suggestions for its size.
    @discardableResult
    public mutating func updateSettings(desk id: UUID, display key: String, now: Date = Date(),
                                        _ change: (inout DisplaySettings) -> Void) -> Bool {
        guard let i = desks.firstIndex(where: { $0.id == id }) else { return false }
        let size = desks[i].displays.first { $0.key == key }?.bounds.cgRect.size ?? .zero
        let old = desks[i].settings[key]
        var settings = old ?? .suggested(for: size)
        change(&settings)
        settings.grid = settings.grid.clamped
        if let old, old.sameContent(as: settings) { return false }
        settings.modified = DeskSync.stamp(now)
        desks[i].settings[key] = settings
        return true
    }

    /// A desk for displays seen together for the first time: named as WindowKeeper names
    /// the same set (`knownNames`, by signature), else after its displays, and seeded from
    /// the most similar desk already known.
    ///
    /// The same desk on another Mac that shares (`others`) gives its name, when WindowKeeper
    /// has none for it, and its grids and palettes.
    public func newDesk(for displays: [LiveDisplay], knownNames: [String: String] = [:], others: [DeskLibrary] = [],
                        now: Date = Date()) -> Desk {
        let signature = DeskSignature.make(displays.map(\.key))
        let records = displays.map(\.record)
        let twinName = others.filter { $0.shares && $0.machineID != machineID }
            .compactMap { $0.desk(withSignature: signature) }.max { $0.lastUsed < $1.lastUsed }?.name
        let name = uniqueName(knownNames[signature] ?? twinName ?? DeskSignature.defaultName(for: records))
        return Desk(name: name, signature: signature, displays: records,
                    settings: seededSettings(for: displays, others: others), created: now, lastUsed: now)
    }

    /// The desk list: the current desk first, then the most recently used.
    public func listed(current: UUID?) -> [Desk] {
        desks.sorted { a, b in
            if (a.id == current) != (b.id == current) { return a.id == current }
            return a.lastUsed > b.lastUsed
        }
    }

    /// The desk you're at can't be deleted: GridLock would only make it again.
    public func canDelete(_ id: UUID, current: UUID?) -> Bool {
        id != current && desks.contains { $0.id == id }
    }

    /// Adds a custom layout, or replaces the one with the same id.
    public mutating func saveCustomLayout(_ layout: CustomLayout, now: Date = Date()) {
        var layout = layout
        if let i = customLayouts.firstIndex(where: { $0.id == layout.id }) {
            let old = customLayouts[i]
            guard old.name != layout.name || old.zones != layout.zones else { return }
            layout.modified = DeskSync.stamp(now)
            customLayouts[i] = layout
        } else {
            layout.modified = DeskSync.stamp(now)
            customLayouts.append(layout)
        }
        deletedLayouts[layout.id.uuidString] = nil
    }

    /// Deletes a custom layout and takes it out of every palette that showed it. The
    /// deletion is remembered, so other Macs delete it too.
    public mutating func removeCustomLayout(_ id: UUID, now: Date = Date()) {
        customLayouts.removeAll { $0.id == id }
        deletedLayouts[id.uuidString] = DeskSync.stamp(now)
        for d in desks.indices {
            for key in desks[d].settings.keys {
                desks[d].settings[key]?.palette.removeAll { $0.kind == .custom(id: id) }
            }
        }
    }

    /// How many palettes, across all desks, show a custom layout.
    public func paletteCount(using id: UUID) -> Int {
        desks.reduce(0) { sum, desk in
            sum + desk.settings.values.filter { $0.palette.contains { $0.kind == .custom(id: id) } }.count
        }
    }
}

/// The picture of a desk in Settings: its displays drawn to scale, in their arrangement.
public enum DeskPicture {
    /// The displays' frames scaled to fit `size`, less `inset` on every side, keeping their
    /// proportions and arrangement, centered.
    public static func fit(_ frames: [CGRect], in size: CGSize, inset: CGFloat = 0) -> [CGRect] {
        guard let first = frames.first else { return [] }
        let union = frames.dropFirst().reduce(first) { $0.union($1) }
        let room = CGSize(width: max(size.width - 2 * inset, 1), height: max(size.height - 2 * inset, 1))
        guard union.width > 0, union.height > 0 else { return frames.map { _ in .zero } }
        let scale = min(room.width / union.width, room.height / union.height)
        let offset = CGPoint(x: (size.width - union.width * scale) / 2, y: (size.height - union.height * scale) / 2)
        return frames.map { f in
            CGRect(x: offset.x + (f.minX - union.minX) * scale, y: offset.y + (f.minY - union.minY) * scale,
                   width: f.width * scale, height: f.height * scale)
        }
    }
}

/// The desk names WindowKeeper has given, by desk signature. WindowKeeper and GridLock key
/// displays the same way, so a signature WindowKeeper knows is the same set of displays.
/// GridLock only ever reads WindowKeeper's file.
public enum WindowKeeperNames {
    private struct File: Decodable {
        struct Profile: Decodable {
            var name: String?
            var signature: String?
        }
        var profiles: [Profile]?
    }

    /// Signature → name, skipping profiles with no name. The first profile wins when two
    /// share a signature.
    public static func parse(_ data: Data) -> [String: String] {
        guard let file = try? JSONDecoder().decode(File.self, from: data) else { return [:] }
        var result: [String: String] = [:]
        for profile in file.profiles ?? [] {
            guard let signature = profile.signature, !signature.isEmpty,
                  let name = profile.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
                  result[signature] == nil else { continue }
            result[signature] = name
        }
        return result
    }
}
