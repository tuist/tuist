import Foundation
import TuistAsyncQueue

public extension AsyncQueue {
    class func run(executionBlock: @escaping () throws -> Void) throws {
        try AsyncQueue.shared = AsyncQueue(dispatchers: [], executionBlock: executionBlock)
    }
}
