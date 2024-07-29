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
    public func concurrentCompactMap<B: Sendable>(_ transform: @Sendable @escaping (Element) async throws -> B?) async throws
        -> [B]
    {
        let tasks = map { element in
            Task {
                try await transform(element)
            }
        }
        var values = [B]()
        for element in tasks {
            if let element = try await element.value {
                values.append(element)
            }
        }
        return values
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

//
// Concurrent Map / For Each
// based on https://talk.objc.io/episodes/S01E90-concurrent-map
//
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
