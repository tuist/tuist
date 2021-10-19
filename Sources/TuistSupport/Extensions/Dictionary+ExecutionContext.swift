public extension Dictionary {
    /// Map (with execution context)
    ///
    /// - Parameters:
    ///   - context: The execution context to perform the `transform` with
    ///   - transform: The transformation closure to apply to the dictionary
    func map<B>(context: ExecutionContext, _ transform: (Key, Value) throws -> B) rethrows -> [B] {
        return try map { ($0.key, $0.value) }
            .map(context: context, transform)
    }

    /// Compact map (with execution context)
    ///
    /// - Parameters:
    ///   - context: The execution context to perform the `transform` with
    ///   - transform: The transformation closure to apply to the dictionary
    func compactMap<B>(context: ExecutionContext, _ transform: (Key, Value) throws -> B?) rethrows -> [B] {
        return try map { ($0.key, $0.value) }
            .compactMap(context: context, transform)
    }

    /// For Each (with execution context)
    ///
    /// - Parameters:
    ///   - context: The execution context to perform the `perform` operation with
    ///   - transform: The perform closure to call on each element in the dictionary
    func forEach(context: ExecutionContext, _ perform: (Key, Value) throws -> Void) rethrows {
        return try map { ($0.key, $0.value) }
            .forEach(context: context, perform)
    }
}
