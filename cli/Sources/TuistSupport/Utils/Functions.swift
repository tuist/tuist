/// Produces a getter function for a given key path. Useful for composing property access with functions.
///
///     get(\String.count)
///     // (String) -> Int
///
/// - Parameter keyPath: A key path.
/// - Returns: A getter function.
public func get<Root, Value>(_ keyPath: KeyPath<Root, Value>) -> (Root) -> Value { { root in root[keyPath: keyPath] }
}

/// Produces a logical AND function for two given closures. Useful for composing predicates with functions.
///
///    func isFramework(node: GraphNode) -> Bool
///    func isDynamicLibrary(node: GraphNode) -> Bool
///
///     and(isFramework, isDynamicLibrary)
///     // (GraphNode) -> True
///
/// - Returns: A predicate function.
public func and<T>(_ lhs: @escaping (T) -> Bool, _ rhs: @escaping (T) -> Bool) -> (T) -> Bool { { lhs($0) && rhs($0) }
}

/// Produces a logical OR function for two given closures. Useful for composing predicates with functions.
///
///    func isFramework(node: GraphNode) -> Bool
///    func isDynamicLibrary(node: GraphNode) -> Bool
///
///     or(isFramework, isDynamicLibrary)
///     // (GraphNode) -> True
///
/// - Returns: A predicate function.
public func or<T>(_ lhs: @escaping (T) -> Bool, _ rhs: @escaping (T) -> Bool) -> (T) -> Bool { { lhs($0) || rhs($0) }
}

public func pipe<Root, Value, T>(
    _ lhs: @escaping (Root) -> Value,
    _ rhs: @escaping (Value) -> T
) -> (Root) -> T { { rhs(lhs($0)) }
}

public func flip<A, B>(_ ƒ: @escaping (A) -> () -> B) -> () -> (A) -> B { { { ƒ($0)() } }
}
