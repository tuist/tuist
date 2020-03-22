import Foundation

/// Ensures that writing and reading from property annotated with this property wrapper is thread safe
/// Taken from https://www.onswiftwings.com/posts/atomic-property-wrapper/
@propertyWrapper
class Atomic<Value> {
    private var value: Value
    private let lock = NSLock()

    init(wrappedValue value: Value) {
        self.value = value
    }

    var wrappedValue: Value {
        get { load() }
        set { store(newValue: newValue) }
    }

    private func load() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    private func store(newValue: Value) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }
}
