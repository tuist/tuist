import Foundation
import OpenCombine

public extension OpenCombine.Publisher {
    /// Waits for the publisher to complete and then returns the values or the error.
    /// This method blocks the thread from which it's called from so it should be used cautiously.
    func wait() throws -> [Output] {
        var output: [Self.Output] = []
        var error: Self.Failure?

        let semaphore = DispatchSemaphore(value: 0)
        _ = handleEvents(receiveOutput: { _output in
            output.append(_output)
        }, receiveCompletion: { completion in
            if case let .failure(_error) = completion {
                error = _error
            }
            semaphore.signal()
        }, receiveCancel: {
            semaphore.signal()
        })
        semaphore.wait()

        if let error = error {
            throw error
        }
        return output
    }
}
