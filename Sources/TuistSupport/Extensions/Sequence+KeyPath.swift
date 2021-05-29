extension Sequence {
    public func filter(where keyPath: KeyPath<Element, Bool>) -> [Element] {
        filter(get(keyPath))
    }

    public func filter(_ keyPath: KeyPath<Element, Bool>) -> [Element] {
        filter(get(keyPath))
    }

    public func map<Property>(_ keyPath: KeyPath<Element, Property>) -> [Property] {
        map(get(keyPath))
    }

    public func compactMap<Property>(_ keyPath: KeyPath<Element, Property?>) -> [Property] {
        compactMap(get(keyPath))
    }

    public func first(_ keyPath: KeyPath<Element, Bool>) -> Element? {
        first(where: get(keyPath))
    }
}
