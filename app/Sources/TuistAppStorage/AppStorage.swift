import Foundation
import Mockable

public protocol AppStorageKey<Value>: Hashable {
    associatedtype Value: Codable
    static var defaultValue: Self.Value { get }
    static var key: String { get }
}

@Mockable
public protocol AppStoring: Sendable {
    func get<Key: AppStorageKey>(_ key: Key.Type) throws -> Key.Value
    func set<Key: AppStorageKey>(_ key: Key.Type, value: Key.Value) throws
}

public final class AppStorage: AppStoring {
    public init() {}

    public func get<Key: AppStorageKey>(_ key: Key.Type) throws -> Key.Value {
        guard let data = UserDefaults.standard.data(forKey: key.key) else { return key.defaultValue }

        let decoder = JSONDecoder()
        return try decoder.decode(Key.Value.self, from: data)
    }

    public func set<Key: AppStorageKey>(_ key: Key.Type, value: Key.Value) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        UserDefaults.standard.setValue(data, forKey: key.key)
    }
}
