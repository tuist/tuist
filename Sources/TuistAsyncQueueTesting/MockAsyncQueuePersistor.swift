import Foundation
import RxSwift
import TuistAsyncQueue
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
        if let event = event as? U {
            invokedWriteEvent = event
            invokedWriteEvents.append(event)
        }
        return stubbedWriteResult
    }

    public var invokedDeleteEventCount = 0
    public var invokedDeleteCallBack: () -> Void = {}
    public var invokedDeleteEvent: U?
    public var invokedDeleteEvents = [U]()
    public var stubbedDeleteEventResult: Completable = .empty()

    public func delete<T: AsyncQueueEvent>(event: T) -> Completable {
        invokedDeleteEventCount += 1
        if let event = event as? U {
            invokedDeleteEvent = event
            invokedDeleteEvents.append(event)
        }
        invokedDeleteCallBack()
        return stubbedDeleteEventResult
    }

    public var invokedDeleteFilename = false
    public var invokedDeleteFilenameCount = 0
    public var invokedDeleteFilenameParameter: String?
    public var invokedDeleteFilenameParametersList = [String]()
    public var stubbedDeleteFilenameResult: Completable = .empty()

    public func delete(filename: String) -> Completable {
        invokedDeleteFilename = true
        invokedDeleteFilenameCount += 1
        invokedDeleteFilenameParameter = filename
        invokedDeleteFilenameParametersList.append(filename)
        return stubbedDeleteFilenameResult
    }
}
