import Foundation
import TuistAsyncQueue
import TuistCore

public final class MockAsyncQueuePersistor<U: AsyncQueueEvent>: AsyncQueuePersisting {
    public init() {}

    public var invokedReadAll = false
    public var invokedReadAllCount = 0
    public var stubbedReadAllResult: [AsyncQueueEventTuple] = []

    public func readAll() -> [AsyncQueueEventTuple] {
        invokedReadAll = true
        invokedReadAllCount += 1
        return stubbedReadAllResult
    }

    public var invokedWrite = false
    public var invokedWriteCount = 0
    public var invokedWriteEvent: U?
    public var invokedWriteEvents = [U]()

    public func write<T: AsyncQueueEvent>(event: T) {
        invokedWrite = true
        invokedWriteCount += 1
        if let event = event as? U {
            invokedWriteEvent = event
            invokedWriteEvents.append(event)
        }
    }

    public var invokedDeleteEventCount = 0
    public var invokedDeleteCallBack: () -> Void = {}
    public var invokedDeleteEvent: U?
    public var invokedDeleteEvents = [U]()

    public func delete<T: AsyncQueueEvent>(event: T) {
        invokedDeleteEventCount += 1
        if let event = event as? U {
            invokedDeleteEvent = event
            invokedDeleteEvents.append(event)
        }
        invokedDeleteCallBack()
    }

    public var invokedDeleteFilename = false
    public var invokedDeleteFilenameCount = 0
    public var invokedDeleteFilenameParameter: String?
    public var invokedDeleteFilenameParametersList = [String]()

    public func delete(filename: String) {
        invokedDeleteFilename = true
        invokedDeleteFilenameCount += 1
        invokedDeleteFilenameParameter = filename
        invokedDeleteFilenameParametersList.append(filename)
    }
}
