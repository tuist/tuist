// import Foundation
// import TuistCore
//
// public final class MockAsyncQueueDispatcher: AsyncQueueDispatching {
//    init() {}
//
//    public var invokedIdentifierGetter = false
//    public var invokedIdentifierGetterCount = 0
//    public var stubbedIdentifier: String! = ""
//
//    public var identifier: String {
//        invokedIdentifierGetter = true
//        invokedIdentifierGetterCount += 1
//        return stubbedIdentifier
//    }
//
//    public var invokedDispatch = false
//    public var invokedDispatchCount = 0
//    public var invokedDispatchParameters: (event: AsyncQueueEvent, Void)?
//    public var invokedDispatchParametersList = [(event: AsyncQueueEvent, Void)]()
//    public var stubbedDispatchError: Error?
//
//    public func dispatch(event: AsyncQueueEvent) throws {
//        invokedDispatch = true
//        invokedDispatchCount += 1
//        invokedDispatchParameters = (event, ())
//        invokedDispatchParametersList.append((event, ()))
//        if let error = stubbedDispatchError {
//            throw error
//        }
//    }
//
//    public var invokedDispatchPersisted = false
//    public var invokedDispatchPersistedCount = 0
//    public var invokedDispatchPersistedParameters: (data: Data, Void)?
//    public var invokedDispatchPersistedParametersList = [(data: Data, Void)]()
//    public var stubbedDispatchPersistedError: Error?
//
//    public func dispatchPersisted(data: Data) throws {
//        invokedDispatchPersisted = true
//        invokedDispatchPersistedCount += 1
//        invokedDispatchPersistedParameters = (data, ())
//        invokedDispatchPersistedParametersList.append((data, ()))
//        if let error = stubbedDispatchPersistedError {
//            throw error
//        }
//    }
// }
