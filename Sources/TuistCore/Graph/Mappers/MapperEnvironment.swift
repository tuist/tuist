import Foundation

public protocol MapperEnvironmentKey<Value>: Hashable {
    associatedtype Value
    static var defaultValue: Self.Value { get }
}

/// An environment dictionary that holds extra context in mappers
public struct MapperEnvironment {
    private var environment: [ObjectIdentifier: Any] = [:]

    public init() {}

    public subscript<Key: MapperEnvironmentKey>(key: Key.Type) -> Key.Value {
        get {
            environment[ObjectIdentifier(key)] as? Key.Value ?? Key.defaultValue
        }
        set {
            environment[ObjectIdentifier(key)] = newValue
        }
    }
}
