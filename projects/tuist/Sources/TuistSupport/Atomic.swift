import Foundation

/// Ensures that writing and reading from property annotated with this property wrapper is thread safe
/// Taken from https://www.onswiftwings.com/posts/atomic-property-wrapper/
@propertyWrapper
public class Atomic<Value> {
    private var value: Value
    private let lock = NSLock()

    public init(wrappedValue value: Value) {
        self.value = value
    }

    public var wrappedValue: Value {
        get { load() }
        set { store(newValue: newValue) }
    }

    public func modify(_ accessBlock: (inout Value) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        accessBlock(&value)
    }

    private func load() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    private func store(newValue: Value) {
        modify {
            $0 = newValue
        }
    }
}
