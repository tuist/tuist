import Foundation

/// Type that ensures thread safe access to the underlying value.
public final class ThreadSafe<T>: @unchecked Sendable {
    private let _lock: UnsafeMutablePointer<os_unfair_lock> = {
        let lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
        return lock
    }()

    private var _value: T

    /// Returns the value boxed by `ThreadSafe`
    public var value: T {
        return withValue { $0 }
    }

    /**
     Mutates in place the value boxed by `ThreadSafe`

     Example:
     ```
     let array = ThreadSafe([1,2,3])
     array.mutate { $0.append(4) }
     ```
     - Parameter with : block used to mutate the underlying value
     */
    @discardableResult
    public func mutate<Result>(_ body: (inout T) throws -> Result) rethrows -> Result {
        os_unfair_lock_lock(_lock)
        defer { os_unfair_lock_unlock(_lock) }
        return try body(&_value)
    }

    /// Like `mutate`, but passes the value as readonly, returning the result of the closure.
    ///
    /// Example:
    /// ```
    /// let array = ThreadSafe([1, 2, 3])
    /// let sum = array.withValue { $0.reduce(0, +) } // 6
    /// ```
    public func withValue<Result>(_ body: (T) throws -> Result) rethrows -> Result {
        return try mutate {
            try body($0)
        }
    }

    /**

     Example:
     ```
     let array = ThreadSafe([1,2,3]) // ThreadSafe<Array<Int>>
     let optional = ThreadSafe<Int?>(nil)
     let optionalString: ThreadSafe<String?> = ThreadSafe("Initial Value")
     ```

     - Parameter initial : initial value used within the Atmoic box
     */
    public init(_ initial: T) { _value = initial }
}
