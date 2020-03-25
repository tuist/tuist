import Foundation

public struct WeakArray<Element: AnyObject>: Collection {
    private var items: [WeakBox<Element>] = []

    public init(_ elements: [Element]) {
        items = elements.map { WeakBox($0) }
    }
    
    // MARK: - Collection
    
    public var startIndex: Int { return items.startIndex }
    public var endIndex: Int { return items.endIndex }

    public subscript(_ index: Int) -> Element? {
        return items[index].value
    }

    public func index(after idx: Int) -> Int {
        return items.index(after: idx)
    }
}
