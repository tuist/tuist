import Foundation

extension Array where Element: Sendable {
    func concurrentMap<B: Sendable>(
        maxConcurrentTasks: Int,
        _ transform: @Sendable @escaping (Element) async throws -> B
    ) async throws -> [B] {
        try await withThrowingTaskGroup(
            of: B.self,
            returning: [B].self
        ) { group in
            var results: [B] = []
            for (index, element) in enumerated() {
                if index >= maxConcurrentTasks {
                    if let result = try await group.next() {
                        results.append(result)
                    }
                }
                group.addTask {
                    try await transform(element)
                }
            }

            for try await result in group {
                results.append(result)
            }

            return results
        }
    }

    func concurrentCompactMap<B: Sendable>(
        maxConcurrentTasks: Int,
        _ transform: @Sendable @escaping (Element) async throws -> B?
    ) async throws -> [B] {
        try await withThrowingTaskGroup(
            of: B?.self,
            returning: [B].self
        ) { group in
            var results: [B] = []
            for (index, element) in enumerated() {
                if index >= maxConcurrentTasks {
                    if let result = try await group.next() {
                        if let value = result {
                            results.append(value)
                        }
                    }
                }
                group.addTask {
                    try await transform(element)
                }
            }

            for try await result in group {
                if let value = result {
                    results.append(value)
                }
            }

            return results
        }
    }
}
