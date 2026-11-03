import Foundation

/// Grids, palettes and custom layouts shared between the user's Macs.
///
/// Each Mac writes only its own library to iCloud Drive (`DeskStore`); with settings sync
/// on, it reads the libraries of the other Macs that share and folds in what's newer:
/// - Custom layouts: every Mac's, the newest version of each; a deletion newer than a
///   layout's last save removes it everywhere.
/// - A display's grid and palette: from another Mac at the same desk (the same set of
///   displays), when it changed them more recently. Other desks keep their own.
///
/// The merge copies change dates as they are, so a Mac that adopts a change and writes its
/// library back never looks newer than the Mac that made it.
public enum DeskSync {
    /// Change dates are kept to the second, which is what the library file stores, so a
    /// date read back from another Mac compares equal to the one written.
    public static func stamp(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    /// This library with the other Macs' shared changes folded in. Libraries that don't
    /// share, and this Mac's own, are skipped.
    public static func merge(_ local: DeskLibrary, with others: [DeskLibrary]) -> DeskLibrary {
        let shared = others.filter { $0.shares && $0.machineID != local.machineID }
        guard !shared.isEmpty else { return local }
        var result = local

        // Deletions: the latest for each layout.
        for other in shared {
            for (id, when) in other.deletedLayouts where when > (result.deletedLayouts[id] ?? .distantPast) {
                result.deletedLayouts[id] = when
            }
        }

        // Layouts: this Mac's order, then ones only other Macs have; the newest version wins.
        var newest = Dictionary(local.customLayouts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var order = local.customLayouts.map(\.id)
        for other in shared {
            for layout in other.customLayouts {
                if let mine = newest[layout.id] {
                    if (layout.modified ?? .distantPast) > (mine.modified ?? .distantPast) { newest[layout.id] = layout }
                } else {
                    newest[layout.id] = layout
                    order.append(layout.id)
                }
            }
        }
        result.customLayouts = order.compactMap { id in
            guard let layout = newest[id] else { return nil }
            if let deleted = result.deletedLayouts[id.uuidString], deleted >= (layout.modified ?? .distantPast) { return nil }
            return layout
        }

        // Grids and palettes at the same desk.
        let kept = Set(result.customLayouts.map(\.id))
        for d in result.desks.indices {
            let signature = result.desks[d].signature
            for other in shared {
                guard let twin = other.desk(withSignature: signature) else { continue }
                for (key, theirs) in twin.settings {
                    guard let when = theirs.modified,
                          when > (result.desks[d].settings[key]?.modified ?? .distantPast) else { continue }
                    result.desks[d].settings[key] = theirs
                }
            }
            // No palette keeps a layout that's gone.
            for key in Array(result.desks[d].settings.keys) {
                result.desks[d].settings[key]?.palette.removeAll { entry in
                    if case .custom(let id) = entry.kind { return !kept.contains(id) }
                    return false
                }
            }
        }
        return result
    }
}
