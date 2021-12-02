public extension Sequence {
    func filter(where keyPath: KeyPath<Element, Bool>) -> [Element] {
        filter(get(keyPath))
    }

    func filter(_ keyPath: KeyPath<Element, Bool>) -> [Element] {
        filter(get(keyPath))
    }

    func map<Property>(_ keyPath: KeyPath<Element, Property>) -> [Property] {
        map(get(keyPath))
    }

    func compactMap<Property>(_ keyPath: KeyPath<Element, Property?>) -> [Property] {
        compactMap(get(keyPath))
    }

    func first(_ keyPath: KeyPath<Element, Bool>) -> Element? {
        first(where: get(keyPath))
    }
}
