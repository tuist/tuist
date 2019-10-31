extension Sequence {
    public func filter(where keyPath: KeyPath<Element, Bool>) -> [Element] {
        return filter(get(keyPath))
    }

    public func filter(_ keyPath: KeyPath<Element, Bool>) -> [Element] {
        return filter(get(keyPath))
    }

    public func map<Property>(_ keyPath: KeyPath<Element, Property>) -> [Property] {
        return map(get(keyPath))
    }

    public func compactMap<Property>(_ keyPath: KeyPath<Element, Property?>) -> [Property] {
        return compactMap(get(keyPath))
    }

    public func first(_ keyPath: KeyPath<Element, Bool>) -> Element? {
        return first(where: get(keyPath))
    }
}
