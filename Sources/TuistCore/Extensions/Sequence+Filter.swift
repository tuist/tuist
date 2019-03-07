extension Sequence {

    public func filter<T>(_ type: T.Type) -> [T] {
        return compactMap{ $0 as? T }
    }

}
