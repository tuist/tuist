import Foundation

extension Sequence where Element: Sendable {
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
    public func serialCompactMap<T: Sendable>(
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

    /// Filter (with execution context)
    ///
    /// - Parameters:
    ///   - context: The execution context to perform the `perform` operation with
    ///   - perform: The perform closure to call on each element in the array
    func concurrentFilter(_ filter: @Sendable @escaping (Element) async throws -> Bool) async rethrows -> [Element] {
        return try await concurrentCompactMap {
            try await filter($0) ? $0 : nil
        }
    }

    /// Async concurrent compact map
    ///
    /// - Parameters:
    ///   - transform: The transformation closure to apply to the array
    func concurrentCompactMap<B: Sendable>(_ transform: @Sendable @escaping (Element) async throws -> B?) async rethrows
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
}
