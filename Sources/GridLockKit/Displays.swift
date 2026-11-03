import CoreGraphics
import Foundation

/// A rectangle in global screen coordinates with a top-left origin — the space the
/// Accessibility API and `CGDisplayBounds` use. Stored as named fields rather than
/// `CGRect`'s nested arrays so the saved JSON is readable.
public struct Rect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(_ rect: CGRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
    }

    public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

/// A display as a desk last saw it.
public struct DisplayRecord: Codable, Hashable, Sendable {
    /// Stable identity, from the display's serial number where it has a real one. See `DisplayKey`.
    public var key: String
    public var name: String
    public var isBuiltin: Bool
    /// Where it sat in the arrangement, in global top-left coordinates.
    public var bounds: Rect

    public init(key: String, name: String, isBuiltin: Bool, bounds: Rect) {
        self.key = key
        self.name = name
        self.isBuiltin = isBuiltin
        self.bounds = bounds
    }
}

/// A display that is connected right now.
public struct LiveDisplay: Hashable, Sendable {
    public var key: String
    public var name: String
    public var isBuiltin: Bool
    public var isMain: Bool
    /// Whole display, global top-left coordinates.
    public var bounds: CGRect
    /// The part windows may use — below the menu bar, clear of the Dock.
    public var visible: CGRect

    public init(key: String, name: String, isBuiltin: Bool, isMain: Bool, bounds: CGRect, visible: CGRect) {
        self.key = key
        self.name = name
        self.isBuiltin = isBuiltin
        self.isMain = isMain
        self.bounds = bounds
        self.visible = visible
    }

    public var record: DisplayRecord {
        DisplayRecord(key: key, name: name, isBuiltin: isBuiltin, bounds: Rect(bounds))
    }

    /// The index of the display holding most of `frame`, or the one nearest its center
    /// when it lies on none (a window dragged half off every screen).
    public static func index(holding frame: CGRect, in displays: [LiveDisplay]) -> Int? {
        guard !displays.isEmpty else { return nil }
        let areas = displays.map { d -> CGFloat in
            let overlap = d.bounds.intersection(frame)
            return overlap.isNull ? 0 : overlap.width * overlap.height
        }
        if let best = areas.indices.max(by: { areas[$0] < areas[$1] }), areas[best] > 0 { return best }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        func distance(_ d: LiveDisplay) -> CGFloat { hypot(d.bounds.midX - center.x, d.bounds.midY - center.y) }
        return displays.indices.min { distance(displays[$0]) < distance(displays[$1]) }
    }
}

/// Coordinates: AppKit's global space is bottom-left at the main display; Accessibility and
/// `CGDisplayBounds` are top-left. Flipping around the main display's height converts both ways.
public enum ScreenSpace {
    public static func flip(_ rect: CGRect, mainHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: mainHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

public enum DeskSignature {
    /// Order-independent: the same displays are the same desk however they are arranged.
    public static func make(_ keys: [String]) -> String {
        keys.sorted().joined(separator: "|")
    }

    /// The default name for a new desk, from its displays' names, left to right.
    public static func defaultName(for displays: [DisplayRecord]) -> String {
        let ordered = displays.sorted { ($0.bounds.x, $0.bounds.y) < ($1.bounds.x, $1.bounds.y) }
        let names = ordered.map { $0.isBuiltin ? "Built-in" : $0.name }
        return names.isEmpty ? "No Displays" : names.joined(separator: " + ")
    }
}
