import Foundation
import TuistAsyncQueue
import TuistCore

public class MockAsyncQueuer: AsyncQueuing {
    public init() {}

    public var invokedDispatch = false
    public var invokedDispatchCount = 0
    public var invokedDispatchParameters: (event: Any, Void)?
    public var invokedDispatchParametersList = [(event: Any, Void)]()

    public func dispatch(event: some AsyncQueueEvent) throws {
        invokedDispatch = true
        invokedDispatchCount += 1
        invokedDispatchParameters = (event, ())
        invokedDispatchParametersList.append((event, ()))
    }

    public var waitIfCIStub: (() -> Void)?
    public func waitIfCI() {
        waitIfCIStub?()
    }
}
