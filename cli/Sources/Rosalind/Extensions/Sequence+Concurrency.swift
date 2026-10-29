import Foundation

extension Sequence {
    func asyncMap<T: Sendable>(_ transform: @Sendable @escaping (Element) async throws -> T) async throws -> [T]
        where Element: Sendable
    {
        let elements = Array(self)

        if elements.isEmpty {
            return []
        }
        var results = [T?](repeating: nil, count: elements.count)

        try await withThrowingTaskGroup(of: (Int, T).self) { group in
            for (index, element) in elements.enumerated() {
                group.addTask {
                    let result = try await transform(element)
                    return (index, result)
                }
            }
            for try await (index, result) in group {
                results[index] = result
            }
        }
        return results.compactMap { $0 }
    }
}
