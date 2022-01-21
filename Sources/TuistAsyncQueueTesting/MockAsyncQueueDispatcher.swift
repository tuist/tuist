import Foundation
import TuistAsyncQueue
import TuistCore

public enum MockAsyncQueueDispatcherError: Error {
    case dispatchError
}

public class MockAsyncQueueDispatcher: AsyncQueueDispatching {
    public init() {}

    public var invokedIdentifierGetter = false
    public var invokedIdentifierGetterCount = 0
    public var stubbedIdentifier: String! = ""

    public var identifier: String {
        invokedIdentifierGetter = true
        invokedIdentifierGetterCount += 1
        return stubbedIdentifier
    }

    public var invokedDispatch = false
    public var invokedDispatchCallBack: () -> Void = {}
    public var invokedDispatchCount = 0
    public var invokedDispatchParameterEvent: AsyncQueueEvent?
    public var invokedDispatchParametersEventsList = [AsyncQueueEvent]()
    public var stubbedDispatchError: Error?

    public func dispatch(event: AsyncQueueEvent, completion: @escaping () throws -> Void) throws {
        invokedDispatch = true
        invokedDispatchCount += 1
        invokedDispatchParameterEvent = event
        invokedDispatchParametersEventsList.append(event)
        if let error = stubbedDispatchError {
            invokedDispatchCallBack()
            throw error
        }
        invokedDispatchCallBack()
        try completion()
    }

    public var invokedDispatchPersisted = false
    public var invokedDispatchPersistedCount = 0
    public var invokedDispatchPersistedCallBack: () -> Void = {}
    public var invokedDispatchPersistedDataParameter: Data?
    public var invokedDispatchPersistedParametersDataList = [Data]()
    public var stubbedDispatchPersistedError: Error?

    public func dispatchPersisted(data: Data, completion: @escaping () throws -> Void) throws {
        invokedDispatchPersisted = true
        invokedDispatchPersistedCount += 1
        invokedDispatchPersistedDataParameter = data
        invokedDispatchPersistedParametersDataList.append(data)
        if let error = stubbedDispatchPersistedError {
            invokedDispatchPersistedCallBack()
            throw error
        }
        invokedDispatchPersistedCallBack()
        try completion()
    }
}
