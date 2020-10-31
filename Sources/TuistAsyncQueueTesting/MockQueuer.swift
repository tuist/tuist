import Foundation
import TuistAsyncQueue

public final class MockQueuer: Queuing {
    public init() {}

    public var invokedAddOperation = false
    public var invokedAddOperationCount = 0
    public var invokedAddOperationParameters: (operation: Operation, Void)?
    public var invokedAddOperationParametersList = [(operation: Operation, Void)]()

    public func addOperation(_ operation: Operation) {
        invokedAddOperation = true
        invokedAddOperationCount += 1
        invokedAddOperationParameters = (operation, ())
        invokedAddOperationParametersList.append((operation, ()))
    }

    public var invokedResume = false
    public var invokedResumeCount = 0

    public func resume() {
        invokedResume = true
        invokedResumeCount += 1
    }

    public var invokedWaitUntilAllOperationsAreFinished = false
    public var invokedWaitUntilAllOperationsAreFinishedCount = 0

    public func waitUntilAllOperationsAreFinished() {
        invokedWaitUntilAllOperationsAreFinished = true
        invokedWaitUntilAllOperationsAreFinishedCount += 1
    }
}
