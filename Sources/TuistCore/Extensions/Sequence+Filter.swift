extension Sequence {
    public func filter<T>(_: T.Type) -> [T] {
        return compactMap { $0 as? T }
    }
}
