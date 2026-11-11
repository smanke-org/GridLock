/// The last few window moves, newest last, for Undo Move. Generic over what identifies a
/// window so it can be tested without Accessibility.
public struct MoveHistory<Item> {
    public static var limit: Int { 10 }

    public private(set) var items: [Item] = []

    public init() {}

    public mutating func push(_ item: Item) {
        items.append(item)
        if items.count > Self.limit { items.removeFirst(items.count - Self.limit) }
    }

    /// The newest move that is still usable (its window still open, say), dropping any
    /// newer ones that aren't.
    public mutating func popLast(where usable: (Item) -> Bool) -> Item? {
        while let item = items.popLast() {
            if usable(item) { return item }
        }
        return nil
    }

    public func last(where usable: (Item) -> Bool) -> Item? {
        items.last(where: usable)
    }

    /// Takes out the newest item that matches (one window's latest move), leaving the rest.
    public mutating func removeLast(where match: (Item) -> Bool) -> Item? {
        guard let i = items.lastIndex(where: match) else { return nil }
        return items.remove(at: i)
    }

    public var isEmpty: Bool { items.isEmpty }
}

extension MoveHistory: Sendable where Item: Sendable {}
