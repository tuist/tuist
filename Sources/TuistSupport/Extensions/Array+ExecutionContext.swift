import Foundation

/// Execution Context
///
/// Defines a context for operations to be performed in.
/// e.g. `.concurrent` or `.serial`
///
public struct ExecutionContext {
    public enum ExecutionType {
        case serial
        case concurrent
    }

    public var executionType: ExecutionType
    public init(executionType: ExecutionType) {
        self.executionType = executionType
    }

    public static var serial: ExecutionContext {
        ExecutionContext(executionType: .serial)
    }

    public static var concurrent: ExecutionContext {
        ExecutionContext(executionType: .concurrent)
    }
}

public extension Array {
    /// Map (with execution context)
    ///
    /// - Parameters:
    ///   - context: The execution context to perform the `transform` with
    ///   - transform: The transformation closure to apply to the array
    func map<B>(context: ExecutionContext, _ transform: (Element) throws -> B) rethrows -> [B] {
        switch context.executionType {
        case .serial:
            return try map(transform)
        case .concurrent:
            return try concurrentMap(transform)
        }
    }

    /// Compact map (with execution context)
    ///
    /// - Parameters:
    ///   - context: The execution context to perform the `transform` with
    ///   - transform: The transformation closure to apply to the array
    func compactMap<B>(context: ExecutionContext, _ transform: (Element) throws -> B?) rethrows -> [B] {
        switch context.executionType {
        case .serial:
            return try compactMap(transform)
        case .concurrent:
            return try concurrentCompactMap(transform)
        }
    }

    /// For Each (with execution context)
    ///
    /// - Parameters:
    ///   - context: The execution context to perform the `perform` operation with
    ///   - transform: The perform closure to call on each element in the array
    func forEach(context: ExecutionContext, _ perform: (Element) throws -> Void) rethrows {
        switch context.executionType {
        case .serial:
            return try forEach(perform)
        case .concurrent:
            return try concurrentForEach(perform)
        }
    }
}

// MARK: - Private

//
// Concurrent Map / For Each
// based on https://talk.objc.io/episodes/S01E90-concurrent-map
//
extension Array {
    private final class ThreadSafe<A> {
        private var _value: A
        private let queue = DispatchQueue(label: "ThreadSafe")
        init(_ value: A) {
            _value = value
        }

        var value: A {
            queue.sync { _value }
        }

        func atomically(_ transform: @escaping (inout A) -> Void) {
            queue.async {
                transform(&self._value)
            }
        }
    }

    private func concurrentMap<B>(_ transform: (Element) throws -> B) rethrows -> [B] {
        let result = ThreadSafe([Result<B, Error>?](repeating: nil, count: count))
        DispatchQueue.concurrentPerform(iterations: count) { idx in
            let element = self[idx]
            do {
                let transformed = try transform(element)
                result.atomically {
                    $0[idx] = .success(transformed)
                }
            } catch {
                result.atomically {
                    $0[idx] = .failure(error)
                }
            }
        }
        return try result.value.map { try $0!.get() }
    }

    private func concurrentCompactMap<B>(_ transform: (Element) throws -> B?) rethrows -> [B] {
        let result = ThreadSafe([Result<B, Error>?](repeating: nil, count: count))
        DispatchQueue.concurrentPerform(iterations: count) { idx in
            let element = self[idx]
            do {
                guard let transformed = try transform(element) else { return }
                result.atomically {
                    $0[idx] = .success(transformed)
                }
            } catch {
                result.atomically {
                    $0[idx] = .failure(error)
                }
            }
        }
        return try result.value.map { try $0!.get() }
    }

    private func concurrentForEach(_ perform: (Element) throws -> Void) rethrows {
        let result = ThreadSafe([Error?](repeating: nil, count: count))
        DispatchQueue.concurrentPerform(iterations: count) { idx in
            let element = self[idx]
            do {
                try perform(element)
            } catch {
                result.atomically {
                    $0[idx] = error
                }
            }
        }
        return try result.value.compactMap { $0 }.forEach {
            throw $0
        }
    }
}
