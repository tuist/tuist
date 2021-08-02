import Combine
import Foundation

extension Publisher {
    /// It blocks the current thread until the publisher finishes.
    /// - Parameter timeout: Timeout
    /// - Throws: Error thrown by the publisher or as a result of a time out caused by the publishing not finishing in time.
    /// - Returns: List of events sent through the publisher.
    public func toBlocking(timeout: DispatchTime = .now() + .seconds(10)) throws -> [Output] {
        let semaphore = DispatchSemaphore(value: 0)
        var cancellables: Set<AnyCancellable> = Set()
        var values: [Output] = []
        var error: Error?

        sink { completion in
            switch completion {
            case let .failure(_error): error = _error
            default: break
            }
            semaphore.signal()
        } receiveValue: { value in
            values.append(value)
        }
        .store(in: &cancellables)

        _ = semaphore.wait(timeout: timeout)
        if let error = error { throw error }
        return values
    }
}
