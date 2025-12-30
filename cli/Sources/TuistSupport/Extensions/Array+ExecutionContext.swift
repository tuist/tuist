import Foundation

extension Array where Element: Sendable {
    /// Map (with execution context)
    ///
    /// - Parameters:
    ///   - context: The execution context to perform the `transform` with
    ///   - transform: The transformation closure to apply to the array
    public func map<B>(context: ExecutionContext, _ transform: (Element) throws -> B) rethrows -> [B] {
        switch context.executionType {
        case .serial:
            return try map(transform)
        case .concurrent:
            return try concurrentMap(transform)
        }
    }

    /// Async concurrent map
    ///
    /// - Parameters:
    ///   - transform: The transformation closure to apply to the array
    public func concurrentMap<B: Sendable>(_ transform: @Sendable @escaping (Element) async throws -> B) async throws -> [B] {
        let tasks = map { element in
            Task {
                try await transform(element)
            }
        }
        var values = [B]()
        for element in tasks {
            try await values.append(element.value)
        }
        return values
    }

    /// Async concurrent map
    ///
    /// - Parameters:
    ///   - maxConcurrentTasks: Number of max tasks that can run simultaneously
    ///   - transform: The transformation closure to apply to the array
    public func concurrentMap<B>(
        maxConcurrentTasks: Int = Int.max,
        _ transform: @escaping (Element) async throws -> B
    ) async throws -> [B] {
        try await withThrowingTaskGroup(
            of: B.self,
            returning: [B].self
        ) { group in
            var results: [B] = []
            for (index, element) in enumerated() {
                if index > maxConcurrentTasks {
                    if let result = try await group.next() {
                        results.append(result)
                    }
                }
                group.addTask {
                    return try await transform(element)
                }
            }

            for try await result in group {
                results.append(result)
            }

            return results
        }
    }

    /// Compact map (with execution context)
    ///
    /// - Parameters:
    ///   - context: The execution context to perform the `transform` with
    ///   - transform: The transformation closure to apply to the array
    public func compactMap<B>(context: ExecutionContext, _ transform: (Element) throws -> B?) rethrows -> [B] {
        switch context.executionType {
        case .serial:
            return try compactMap(transform)
        case .concurrent:
            return try concurrentCompactMap(transform)
        }
    }

    /// Async concurrent compact map
    ///
    /// - Parameters:
    ///   - transform: The transformation closure to apply to the array
    public func concurrentCompactMap<B: Sendable>(_ transform: @Sendable @escaping (Element) async throws -> B?) async rethrows
        -> [B]
    {
        let tasks = map { element in
            Task {
                try await transform(element)
            }
        }

        return try await tasks.serialCompactMap { task in
            try await task.value
        }
    }

    /// For Each (with execution context)
    ///
    /// - Parameters:
    ///   - context: The execution context to perform the `perform` operation with
    ///   - perform: The perform closure to call on each element in the array
    public func forEach(context: ExecutionContext, _ perform: (Element) throws -> Void) rethrows {
        switch context.executionType {
        case .serial:
            return try forEach(perform)
        case .concurrent:
            return try concurrentForEach(perform)
        }
    }

    /// For Each (with execution context)
    ///
    /// - Parameters:
    ///   - context: The execution context to perform the `perform` operation with
    ///   - perform: The perform closure to call on each element in the array
    public func forEach(context: ExecutionContext, _ perform: @escaping (Element) async throws -> Void) async rethrows {
        switch context.executionType {
        case .serial:
            for item in self {
                try await perform(item)
            }
        case .concurrent:
            return try await concurrentForEach(perform)
        }
    }
}

// MARK: - Private

// Concurrent Map / For Each
// Based on https://talk.objc.io/episodes/S01E90-concurrent-map

extension Array {
    private func concurrentMap<B>(_ transform: (Element) throws -> B) rethrows -> [B] {
        let result = ThreadSafe([Result<B, Error>?](repeating: nil, count: count))
        DispatchQueue.concurrentPerform(iterations: count) { idx in
            let element = self[idx]
            do {
                let transformed = try transform(element)
                result.mutate {
                    $0[idx] = .success(transformed)
                }
            } catch {
                result.mutate {
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
                result.mutate {
                    $0[idx] = .success(transformed)
                }
            } catch {
                result.mutate {
                    $0[idx] = .failure(error)
                }
            }
        }
        return try result.value.compactMap { try $0?.get() }
    }

    /// Filter (with execution context)
    ///
    /// - Parameters:
    ///   - context: The execution context to perform the `perform` operation with
    ///   - perform: The perform closure to call on each element in the array
    public func concurrentFilter(_ filter: @escaping (Element) async throws -> Bool) async rethrows -> [Element] {
        return try await concurrentCompactMap {
            try await filter($0) ? $0 : nil
        }
    }

    private func concurrentForEach(_ perform: (Element) throws -> Void) rethrows {
        let result = ThreadSafe([Error?](repeating: nil, count: count))
        DispatchQueue.concurrentPerform(iterations: count) { idx in
            let element = self[idx]
            do {
                try perform(element)
            } catch {
                result.mutate {
                    $0[idx] = error
                }
            }
        }
        return try result.value.compactMap { $0 }.forEach {
            throw $0
        }
    }

    private func concurrentForEach(_ perform: @escaping (Element) async throws -> Void) async rethrows {
        let result = ThreadSafe([Error?](repeating: nil, count: count))

        await withTaskGroup(of: Void.self) { group in
            for idx in 0 ..< count {
                group.addTask {
                    let element = self[idx]
                    do {
                        try await perform(element)
                    } catch {
                        result.mutate {
                            $0[idx] = error
                        }
                    }
                }
            }
        }

        try result.value.compactMap { $0 }.forEach {
            throw $0
        }
    }
}

extension Set where Element: Sendable {
    /// Filter (with execution context)
    ///
    /// - Parameters:
    ///   - context: The execution context to perform the `perform` operation with
    ///   - perform: The perform closure to call on each element in the array
    public func concurrentFilter(_ filter: @escaping (Element) async throws -> Bool) async rethrows -> Set<Element> {
        return Set(
            try await Array(self).concurrentCompactMap {
                try await filter($0) ? $0 : nil
            }
        )
    }

    public func concurrentMap<B>(_ transform: @escaping (Element) async throws -> B) async throws -> [B] {
        try await Array(self).concurrentMap {
            try await transform($0)
        }
    }
}

extension Sequence {
    /// Taken from: https://github.com/JohnSundell/CollectionConcurrencyKit/blob/b4f23e24b5a1bff301efc5e70871083ca029ff95/Sources/CollectionConcurrencyKit.swift
    /// Transform the sequence into an array of new values using
    /// an async closure that returns optional values. Only the
    /// non-`nil` return values will be included in the new array.
    ///
    /// The closure calls will be performed in order, by waiting for
    /// each call to complete before proceeding with the next one. If
    /// any of the closure calls throw an error, then the iteration
    /// will be terminated and the error rethrown.
    ///
    /// - parameter transform: The transform to run on each element.
    /// - returns: The transformed values as an array. The order of
    ///   the transformed values will match the original sequence,
    ///   except for the values that were transformed into `nil`.
    /// - throws: Rethrows any error thrown by the passed closure.
    public func serialCompactMap<T>(
        _ transform: (Element) async throws -> T?
    ) async rethrows -> [T] {
        var values = [T]()

        for element in self {
            guard let value = try await transform(element) else {
                continue
            }

            values.append(value)
        }

        return values
    }

    /// Transform the sequence into an array of new values using
    /// an async closure that non-optional values.
    ///
    /// The closure calls will be performed in order, by waiting for
    /// each call to complete before proceeding with the next one. If
    /// any of the closure calls throw an error, then the iteration
    /// will be terminated and the error rethrown.
    ///
    /// - parameter transform: The transform to run on each element.
    /// - returns: The transformed values as an array. The order of
    ///   the transformed values will match the original sequence.
    /// - throws: Rethrows any error thrown by the passed closure.
    public func serialMap<T>(
        _ transform: (Element) async throws -> T
    ) async rethrows -> [T] {
        var values = [T]()

        for element in self {
            values.append(try await transform(element))
        }

        return values
    }

    /// Transform the sequence into an array of new values using
    /// an async closure that returns sequences. The returned sequences
    /// will be flattened into the array returned from this function.
    ///
    /// The closure calls will be performed in order, by waiting for
    /// each call to complete before proceeding with the next one. If
    /// any of the closure calls throw an error, then the iteration
    /// will be terminated and the error rethrown.
    ///
    /// - parameter transform: The transform to run on each element.
    /// - returns: The transformed values as an array. The order of
    ///   the transformed values will match the original sequence,
    ///   with the results of each closure call appearing in-order
    ///   within the returned array.
    /// - throws: Rethrows any error thrown by the passed closure.
    func serialFlatMap<T: Sequence>(
        _ transform: (Element) async throws -> T
    ) async rethrows -> [T.Element] {
        var values = [T.Element]()

        for element in self {
            try await values.append(contentsOf: transform(element))
        }

        return values
    }

    /// Transform the sequence into an array of new values using
    /// an async closure that returns sequences. The returned sequences
    /// will be flattened into the array returned from this function.
    ///
    /// The closure calls will be performed concurrently, but the call
    /// to this function won't return until all of the closure calls
    /// have completed.
    ///
    /// - parameter priority: Any specific `TaskPriority` to assign to
    ///   the async tasks that will perform the closure calls. The
    ///   default is `nil` (meaning that the system picks a priority).
    /// - parameter transform: The transform to run on each element.
    /// - returns: The transformed values as an array. The order of
    ///   the transformed values will match the original sequence,
    ///   with the results of each closure call appearing in-order
    ///   within the returned array.
    public func concurrentFlatMap<T: Sequence>(
        withPriority priority: TaskPriority? = nil,
        _ transform: @escaping (Element) async throws -> T
    ) async rethrows -> [T.Element] {
        let tasks = map { element in
            Task(priority: priority) {
                try await transform(element)
            }
        }

        return try await tasks.serialFlatMap { task in
            try await task.value
        }
    }

    /// Transform the sequence into an array of new values using
    /// an async closure that returns optional values. Only the
    /// non-`nil` return values will be included in the new array.
    ///
    /// The closure calls will be performed concurrently, but the call
    /// to this function won't return until all of the closure calls
    /// have completed.
    ///
    /// - parameter priority: Any specific `TaskPriority` to assign to
    ///   the async tasks that will perform the closure calls. The
    ///   default is `nil` (meaning that the system picks a priority).
    /// - parameter transform: The transform to run on each element.
    /// - returns: The transformed values as an array. The order of
    ///   the transformed values will match the original sequence,
    ///   except for the values that were transformed into `nil`.
    public func concurrentCompactMap<T>(
        withPriority priority: TaskPriority? = nil,
        _ transform: @escaping (Element) async throws -> T?
    ) async rethrows -> [T] {
        let tasks = map { element in
            Task(priority: priority) {
                try await transform(element)
            }
        }

        return try await tasks.serialCompactMap { task in
            try await task.value
        }
    }
}
