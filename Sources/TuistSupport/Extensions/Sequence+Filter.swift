extension Sequence {
    public func filter<T>(_: T.Type) -> [T] {
        compactMap { $0 as? T }
    }
}
