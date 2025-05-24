import Foundation
import Mockable
import Queuer
import Testing
import TuistCore
import TuistSupport

@testable import TuistAsyncQueue
@testable import TuistAsyncQueueTesting
@testable import TuistSupportTesting

struct AsyncQueueTests {
    private var subject: AsyncQueue!
    private let dispatcher1ID = "Dispatcher1"
    private let dispatcher2ID = "Dispatcher2"
    private var mockAsyncQueueDispatcher1: MockAsyncQueueDispatcher!
    private var mockAsyncQueueDispatcher2: MockAsyncQueueDispatcher!
    private var mockPersistor: MockAsyncQueuePersistor<AnyAsyncQueueEvent>!
    private var mockQueuer: MockQueuer!
    private let timeout = 3.0

    init() {
        mockAsyncQueueDispatcher1 = MockAsyncQueueDispatcher()
        mockAsyncQueueDispatcher1.stubbedIdentifier = dispatcher1ID
        mockAsyncQueueDispatcher2 = MockAsyncQueueDispatcher()
        mockAsyncQueueDispatcher2.stubbedIdentifier = dispatcher2ID
        mockPersistor = MockAsyncQueuePersistor()
        mockQueuer = MockQueuer()
    }

    func makeSubject(
        queue: Queuing? = nil,
        persistor: AsyncQueuePersisting? = nil
    ) -> AsyncQueue {
        let asyncQueue = AsyncQueue(
            queue: queue ?? mockQueuer,
            persistor: persistor ?? mockPersistor
        )
        asyncQueue.register(dispatcher: mockAsyncQueueDispatcher1)
        asyncQueue.register(dispatcher: mockAsyncQueueDispatcher2)
        return asyncQueue
    }

    @Test mutating func test_dispatch_eventIsPersisted() throws {
        // Given
        let event = AnyAsyncQueueEvent(dispatcherId: dispatcher1ID)
        subject = makeSubject()

        // When
        try subject.dispatch(event: event)

        // Then
        let persistedEvent = try #require(mockPersistor.invokedWriteEvent)
        #expect(event.id == persistedEvent.id)
    }

    @Test mutating func test_dispatch_eventIsQueued() throws {
        // Given
        let event = AnyAsyncQueueEvent(dispatcherId: dispatcher1ID)
        subject = makeSubject()

        // When
        try subject.dispatch(event: event)
        // Then
        let queuedOperation = try #require(mockQueuer.invokedAddOperationParameterOperation as? ConcurrentOperation)
        #expect(queuedOperation.name == event.id.uuidString)
    }

    @Test mutating func test_dispatch_eventIsPersistedOnDispatcherSuccess() async throws {
        // Given
        let event = AnyAsyncQueueEvent(dispatcherId: dispatcher1ID)
        subject = makeSubject(queue: Queuer.shared)

        // When
        try await confirmation { confirm in
            mockPersistor.invokedDeleteCallBack = {
                confirm()
            }
            try subject.dispatch(event: event)
        }

        // Then
        let deletedEvent = try #require(mockPersistor.invokedDeleteEvent)
        #expect(event.id == deletedEvent.id)
    }

    @Test mutating func test_dispatch_eventIsPersistedOnCompletion() throws {
        // Given
        let event = AnyAsyncQueueEvent(dispatcherId: dispatcher1ID)
        subject = makeSubject(queue: Queuer.shared)

        // When
        try subject.dispatch(event: event)

        // Then
        #expect(mockPersistor.invokedWriteEvent?.id == event.id)
    }

    @Test mutating func test_dispatch_eventIsDispatchedByTheRightDispatcher() async throws {
        // Given
        let event = AnyAsyncQueueEvent(dispatcherId: dispatcher1ID)
        subject = makeSubject(queue: Queuer.shared)

        // When
        try await confirmation { confirmation in
            mockAsyncQueueDispatcher1.invokedDispatchCallBack = {
                confirmation()
            }
            try subject.dispatch(event: event)
        }

        // Then
        let dispatchedEvent = try #require(mockAsyncQueueDispatcher1.invokedDispatchParameterEvent)
        #expect(event.id == dispatchedEvent.id)
        #expect(mockAsyncQueueDispatcher1.invokedDispatchCount == 1)
        #expect(mockAsyncQueueDispatcher2.invokedDispatchCount == 0)
        #expect(mockAsyncQueueDispatcher2.invokedDispatchParameterEvent == nil)
    }

    @Test mutating func test_dispatch_queuerTriesThreeTimesToDispatch() async throws {
        // Given
        let event = AnyAsyncQueueEvent(dispatcherId: dispatcher1ID)
        subject = makeSubject(queue: Queuer.shared)
        mockAsyncQueueDispatcher1.stubbedDispatchError = MockAsyncQueueDispatcherError.dispatchError

        // When
        var count = 0
        try await confirmation { confirmation in
            mockAsyncQueueDispatcher1.invokedDispatchCallBack = {
                count += 1
                if count == 3 {
                    confirmation()
                }
            }

            try subject.dispatch(event: event)
        }

        // Then
        #expect(count == 3)
    }

    @Test mutating func test_dispatch_doesNotDeleteEventOnError() async throws {
        // Given
        let event = AnyAsyncQueueEvent(dispatcherId: dispatcher1ID)
        subject = makeSubject(queue: Queuer.shared)
        mockAsyncQueueDispatcher1.stubbedDispatchError = MockAsyncQueueDispatcherError.dispatchError

        // When
        var count = 0
        try await confirmation { confirmation in
            mockAsyncQueueDispatcher1.invokedDispatchCallBack = {
                count += 1
                if count == 3 {
                    confirmation()
                }
            }
            try subject.dispatch(event: event)
        }

        // Then
        #expect(count == 3)
        #expect(mockPersistor.invokedDeleteEventCount == 0)
    }

    @Test(.withMockedEnvironment) mutating func test_waits_for_queue_to_finish_when_CI() async throws {
        // Given
        let eventTuple1: AsyncQueueEventTuple = makeEventTuple(id: 1)
        mockPersistor.stubbedReadAllResult = [eventTuple1]
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = ["CI": "1"]

        // When
        subject = makeSubject(queue: Queuer.shared)
        await subject.start()

        // Then
        #expect(Queuer.shared.operationCount == 0)
    }

    @Test(.withMockedEnvironment) mutating func test_start_readsPersistedEventsInitialization() async throws {
        // Given
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [:]

        let eventTuple1: AsyncQueueEventTuple = makeEventTuple(id: 1)
        let eventTuple2: AsyncQueueEventTuple = makeEventTuple(id: 2)
        let eventTuple3: AsyncQueueEventTuple = makeEventTuple(id: 3)
        mockPersistor.stubbedReadAllResult = [eventTuple1, eventTuple2, eventTuple3]

        // When
        subject = makeSubject()
        await subject.start()

        // Then
        let numberOfOperationsQueued = mockQueuer.invokedAddOperationCount
        #expect(numberOfOperationsQueued == 3)

        let queuedOperation1 = try #require(mockQueuer.invokedAddOperationParametersOperationsList[0] as? ConcurrentOperation)
        #expect(queuedOperation1.name == eventTuple1.id.uuidString)
        let queuedOperation2 = try #require(mockQueuer.invokedAddOperationParametersOperationsList[1] as? ConcurrentOperation)
        #expect(queuedOperation2.name == eventTuple2.id.uuidString)
        let queuedOperation3 = try #require(mockQueuer.invokedAddOperationParametersOperationsList[2] as? ConcurrentOperation)
        #expect(queuedOperation3.name == eventTuple3.id.uuidString)
    }

    @Test(.withMockedEnvironment) mutating func test_start_persistedEventIsDispatchedByTheRightDispatcher() async throws {
        // Given
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [:]
        let eventTuple1: AsyncQueueEventTuple = makeEventTuple(id: 1)
        mockPersistor.stubbedReadAllResult = [eventTuple1]

        // When
        await confirmation { confirmation in
            mockAsyncQueueDispatcher1.invokedDispatchPersistedCallBack = {
                confirmation()
            }

            subject = makeSubject(queue: Queuer.shared)
            await subject.start()
        }

        // Then
        let dispatchedEventData = try #require(mockAsyncQueueDispatcher1.invokedDispatchPersistedDataParameter)

        #expect(eventTuple1.data == dispatchedEventData)
        #expect(mockAsyncQueueDispatcher1.invokedDispatchPersistedCount == 1)
        #expect(mockAsyncQueueDispatcher2.invokedDispatchPersistedCount == 0)
    }

    @Test(.withMockedEnvironment) mutating func test_start_sentPersistedEventIsThenDeleted() async throws {
        // Given
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [:]
        let id: UInt = 1
        let eventTuple1: AsyncQueueEventTuple = makeEventTuple(id: id)
        mockPersistor.stubbedReadAllResult = [eventTuple1]
        subject = makeSubject(queue: Queuer.shared)

        // When
        await confirmation { confirmation in
            mockAsyncQueueDispatcher1.invokedDispatchPersistedCallBack = {
                confirmation()
            }
            await subject.start()
        }

        // Then
        let filename = try #require(mockPersistor.invokedDeleteFilenameParameter)
        #expect(filename == self.filename(with: id))
    }

    // MARK: Private

    private func makeEventTuple(id: UInt, dispatcherId: String? = nil) -> AsyncQueueEventTuple {
        (
            dispatcherId: dispatcherId ?? dispatcher1ID,
            id: UUID(),
            date: Date(),
            data: data(with: id),
            filename: filename(with: id)
        )
    }

    private func data(with id: UInt) -> Data {
        withUnsafeBytes(of: id) { Data($0) }
    }

    private func filename(with id: UInt) -> String {
        "filename-\(id)"
    }
}
