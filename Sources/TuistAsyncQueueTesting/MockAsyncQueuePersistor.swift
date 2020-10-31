import Foundation
import TuistAsyncQueue
import RxSwift
import TuistCore

public final class MockAsyncQueuePersistor<U: AsyncQueueEvent>: AsyncQueuePersisting {

    public init() {}
    
    public var invokedReadAll = false
    public var invokedReadAllCount = 0
    public var stubbedReadAllResult: Single<[AsyncQueueEventTuple]> = Single.just([])

    public func readAll() -> Single<[AsyncQueueEventTuple]> {
        invokedReadAll = true
        invokedReadAllCount += 1
        return stubbedReadAllResult
    }

    public var invokedWrite = false
    public var invokedWriteCount = 0
    public var invokedWriteEvent: U?
    public var invokedWriteEvents = [U]()
    public var stubbedWriteResult: Completable = .empty()

    public func write<T: AsyncQueueEvent>(event: T) -> Completable {
        invokedWrite = true
        invokedWriteCount += 1
        invokedWriteEvent = event as? U
        invokedWriteEvents.append(event as! U)
        return stubbedWriteResult
    }

    public var invokedDeleteEventCount = 0
    public var invokedDeleteCallBack: () -> Void = {}
    public var invokedDeleteEvent: U?
    public var invokedDeleteEvents = [U]()
    public var stubbedDeleteEventResult: Completable = .empty()
    
    public func delete<T: AsyncQueueEvent>(event: T) -> Completable {
        invokedDeleteEventCount += 1
        invokedDeleteEvent = event as? U
        invokedDeleteEvents.append(event as! U)
        invokedDeleteCallBack()
        return stubbedDeleteEventResult
    }

    public var invokedDeleteFilename = false
    public var invokedDeleteFilenameCount = 0
    public var invokedDeleteFilenameParameters: (filename: String, Void)?
    public var invokedDeleteFilenameParametersList = [(filename: String, Void)]()
    public var stubbedDeleteFilenameResult: Completable!

    public func delete(filename: String) -> Completable {
        invokedDeleteFilename = true
        invokedDeleteFilenameCount += 1
        invokedDeleteFilenameParameters = (filename, ())
        invokedDeleteFilenameParametersList.append((filename, ()))
        return stubbedDeleteFilenameResult
    }
}
