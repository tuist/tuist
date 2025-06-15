import Foundation

@propertyWrapper
public final class Cached<T: Sendable> {
    private let _cache: Caching<T>
    public var wrappedValue: T {
        return _cache.value
    }

    init(_ lazyValue: @Sendable @escaping () -> T) {
        _cache = Caching(lazyValue)
    }
}

public final class Caching<T: Sendable> {
    private let _value: ThreadSafe<T?> = ThreadSafe(nil)
    public var value: T {
        return _value.mutate { value in
            if let value {
                return value
            } else {
                let realizedValue = builder()
                value = realizedValue
                return realizedValue
            }
        }
    }

    let builder: @Sendable () -> T

    public init(_ lazyValue: @Sendable @escaping () -> T) {
        builder = lazyValue
    }
}

public final class ThrowableCaching<T: Sendable> {
    private let _value: ThreadSafe<T?> = ThreadSafe(nil)
    public var value: T {
        get throws {
            return try _value.mutate { value in
                if let value {
                    return value
                } else {
                    let realizedValue = try builder()
                    value = realizedValue
                    return realizedValue
                }
            }
        }
    }

    let builder: @Sendable () throws -> T

    public init(_ lazyValue: @Sendable @escaping () throws -> T) {
        builder = lazyValue
    }
}
