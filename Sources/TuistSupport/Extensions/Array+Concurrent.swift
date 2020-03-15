import Foundation

//
// Concurrent Map
// based on https://talk.objc.io/episodes/S01E90-concurrent-map
//

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

public extension Array {
    func concurrentMap<B>(_ transform: (Element) throws -> B) rethrows -> [B] {
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

    func concurrentForEach(_ perform: (Element) throws -> Void) rethrows {
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
