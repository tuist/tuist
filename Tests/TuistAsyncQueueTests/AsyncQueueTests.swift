import Foundation
import Queuer
import RxBlocking
import RxSwift
import TuistCore
import TuistSupport
import XCTest

@testable import TuistAsyncQueue
@testable import TuistAsyncQueueTesting
@testable import TuistSupportTesting

final class AsyncQueueTests: TuistUnitTestCase {
    var subject: AsyncQueue!

    let dispatcher1ID = "Dispatcher1"
    let dispatcher2ID = "Dispatcher2"

    var mockAsyncQueueDispatcher1: MockAsyncQueueDispatcher!
    var mockAsyncQueueDispatcher2: MockAsyncQueueDispatcher!

    var mockCIChecker: MockCIChecker!

    var mockPersistor: MockAsyncQueuePersistor<AnyAsyncQueueEvent>!
    var mockQueuer: MockQueuer!

    let timeout = 3.0

    override func setUp() {
        super.setUp()
        mockAsyncQueueDispatcher1 = MockAsyncQueueDispatcher()
        mockAsyncQueueDispatcher1.stubbedIdentifier = dispatcher1ID

        mockAsyncQueueDispatcher2 = MockAsyncQueueDispatcher()
        mockAsyncQueueDispatcher2.stubbedIdentifier = dispatcher2ID

        mockCIChecker = MockCIChecker()
        mockPersistor = MockAsyncQueuePersistor()
        mockQueuer = MockQueuer()
    }

    override func tearDown() {
        mockAsyncQueueDispatcher1 = nil
        mockAsyncQueueDispatcher2 = nil
        mockCIChecker = nil
        mockPersistor = nil
        mockQueuer = nil
        subject = nil
        super.tearDown()
    }

    func makeSubject(
        queue: Queuing? = nil,
        ciChecker: CIChecking? = nil,
        persistor: AsyncQueuePersisting? = nil,
        dispatchers: [AsyncQueueDispatching]? = nil
    ) -> AsyncQueue {
        let asyncQueue = AsyncQueue(
            queue: queue ?? mockQueuer,
            ciChecker: ciChecker ?? mockCIChecker,
            persistor: persistor ?? mockPersistor,
            persistedEventsSchedulerType: MainScheduler())
        asyncQueue.register(dispatcher: mockAsyncQueueDispatcher1)
        asyncQueue.register(dispatcher: mockAsyncQueueDispatcher2)
        return asyncQueue
    }

    func test_dispatch_eventIsPersisted() throws {
        var didComplete = false
        // Given
        let event = AnyAsyncQueueEvent(dispatcherId: dispatcher1ID)
        subject = makeSubject()

        // When
        subject.dispatch(event: event) {
            // Then
            guard let persistedEvent = self.mockPersistor.invokedWriteEvent else {
                XCTFail("Event not passed to the persistor")
                return
            }
            XCTAssertEqual(event.id, persistedEvent.id)
            didComplete = true
        }
        XCTAssertTrue(didComplete)
    }

    func test_dispatch_eventIsQueued() throws {
        var didComplete = false

        // Given
        let event = AnyAsyncQueueEvent(dispatcherId: dispatcher1ID)
        subject = makeSubject()

        // When
        subject.dispatch(event: event) {
            // Then
            guard let queuedOperation = self.mockQueuer.invokedAddOperationParameterOperation as? ConcurrentOperation else {
                XCTFail("Operation not added to the queuer")
                return
            }
            XCTAssertEqual(queuedOperation.name, event.id.uuidString)
            didComplete = true
        }
        XCTAssertTrue(didComplete)
    }

    func test_dispatch_eventIsPersistedOnDispatcherSuccess() throws {
        // Given
        let event = AnyAsyncQueueEvent(dispatcherId: dispatcher1ID)
        subject = makeSubject(queue: Queuer.shared)
        let expectation = XCTestExpectation(description: #function)
        mockPersistor.invokedDeleteCallBack = {
            expectation.fulfill()
        }
        // When
        subject.dispatch(event: event) {
            self.wait(for: [expectation], timeout: self.timeout)
            guard let deletedEvent = self.mockPersistor.invokedDeleteEvent else {
                XCTFail("Event was not deleted by the persistor")
                return
            }
            // Then
            XCTAssertEqual(event.id, deletedEvent.id)
        }
    }

    func test_dispatch_eventIsPersistedOnCompletion() throws {
        // Given
        let event = AnyAsyncQueueEvent(dispatcherId: dispatcher1ID)
        subject = makeSubject(queue: Queuer.shared)
        let expectation = XCTestExpectation(description: #function)

        // When
        subject.dispatch(event: event) {
            // Then
            XCTAssertEqual(self.mockPersistor.invokedWriteEvent?.id, event.id)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout)
    }

    func test_dispatch_eventIsDispatchedByTheRightDispatcher() throws {
        // Given
        let event = AnyAsyncQueueEvent(dispatcherId: dispatcher1ID)
        subject = makeSubject(queue: Queuer.shared)
        let expectation = XCTestExpectation(description: #function)
        mockAsyncQueueDispatcher1.invokedDispatchCallBack = {
            expectation.fulfill()
        }
        // When
        subject.dispatch(event: event) {
            self.wait(for: [expectation], timeout: self.timeout)

            guard let dispatchedEvent = self.mockAsyncQueueDispatcher1.invokedDispatchParameterEvent else {
                XCTFail("Event was not dispatched")
                return
            }
            // Then
            XCTAssertEqual(event.id, dispatchedEvent.id)
            XCTAssertEqual(self.mockAsyncQueueDispatcher1.invokedDispatchCount, 1)
            XCTAssertEqual(self.mockAsyncQueueDispatcher2.invokedDispatchCount, 0)
            XCTAssertNil(self.mockAsyncQueueDispatcher2.invokedDispatchParameterEvent)
        }
    }

    func test_dispatch_queuerTriesThreeTimesToDispatch() throws {
        // Given
        let event = AnyAsyncQueueEvent(dispatcherId: dispatcher1ID)
        subject = makeSubject(queue: Queuer.shared)
        mockAsyncQueueDispatcher1.stubbedDispatchError = MockAsyncQueueDispatcherError.dispatchError
        let expectation = XCTestExpectation(description: #function)

        var count = 0
        mockAsyncQueueDispatcher1.invokedDispatchCallBack = {
            count += 1
            if count == 3 {
                expectation.fulfill()
            }
        }

        // When
        subject.dispatch(event: event) {
            self.wait(for: [expectation], timeout: self.timeout)
            // Then
            XCTAssertEqual(count, 3)
        }
    }

    func test_dispatch_doesNotDeleteEventOnError() throws {
        // Given
        let event = AnyAsyncQueueEvent(dispatcherId: dispatcher1ID)
        subject = makeSubject(queue: Queuer.shared)
        mockAsyncQueueDispatcher1.stubbedDispatchError = MockAsyncQueueDispatcherError.dispatchError
        let expectation = XCTestExpectation(description: #function)

        var count = 0
        mockAsyncQueueDispatcher1.invokedDispatchCallBack = {
            count += 1
            if count == 3 {
                expectation.fulfill()
            }
        }

        // When
        subject.dispatch(event: event) {
            self.wait(for: [expectation], timeout: self.timeout)
            // Then
            XCTAssertEqual(count, 3)
            XCTAssertEqual(self.mockPersistor.invokedDeleteEventCount, 0)
        }
    }

    func test_start_readsPersistedEventsInitialization() throws {
        // Given
        let eventTuple1: AsyncQueueEventTuple = makeEventTuple(id: 1)
        let eventTuple2: AsyncQueueEventTuple = makeEventTuple(id: 2)
        let eventTuple3: AsyncQueueEventTuple = makeEventTuple(id: 3)
        mockPersistor.stubbedReadAllResult = .just([eventTuple1, eventTuple2, eventTuple3])

        // When
        subject = makeSubject()
        subject.start()

        // Then
        let numberOfOperationsQueued = mockQueuer.invokedAddOperationCount
        XCTAssertEqual(numberOfOperationsQueued, 3)

        guard let queuedOperation1 = mockQueuer.invokedAddOperationParametersOperationsList[0] as? ConcurrentOperation else {
            XCTFail("Operation for event tuple 1 not added to the queuer")
            return
        }
        XCTAssertEqual(queuedOperation1.name, eventTuple1.id.uuidString)

        guard let queuedOperation2 = mockQueuer.invokedAddOperationParametersOperationsList[1] as? ConcurrentOperation else {
            XCTFail("Operation for event tuple 2 not added to the queuer")
            return
        }
        XCTAssertEqual(queuedOperation2.name, eventTuple2.id.uuidString)

        guard let queuedOperation3 = mockQueuer.invokedAddOperationParametersOperationsList[2] as? ConcurrentOperation else {
            XCTFail("Operation for event tuple 3 not added to the queuer")
            return
        }
        XCTAssertEqual(queuedOperation3.name, eventTuple3.id.uuidString)
    }

    func test_start_persistedEventIsDispatchedByTheRightDispatcher() throws {
        // Given
        let eventTuple1: AsyncQueueEventTuple = makeEventTuple(id: 1)
        mockPersistor.stubbedReadAllResult = .just([eventTuple1])

        let expectation = XCTestExpectation(description: #function)
        mockAsyncQueueDispatcher1.invokedDispatchPersistedCallBack = {
            expectation.fulfill()
        }

        // When
        subject = makeSubject(queue: Queuer.shared)
        subject.start()

        // Then
        wait(for: [expectation], timeout: timeout)
        guard let dispatchedEventData = mockAsyncQueueDispatcher1.invokedDispatchPersistedDataParameter else {
            XCTFail("Data from persisted event was not dispatched")
            return
        }
        XCTAssertEqual(eventTuple1.data, dispatchedEventData)
        XCTAssertEqual(mockAsyncQueueDispatcher1.invokedDispatchPersistedCount, 1)
        XCTAssertEqual(mockAsyncQueueDispatcher2.invokedDispatchPersistedCount, 0)
    }

    func test_start_sentPersistedEventIsThenDeleted() throws {
        // Given
        let id: UInt = 1
        let eventTuple1: AsyncQueueEventTuple = makeEventTuple(id: id)
        mockPersistor.stubbedReadAllResult = .just([eventTuple1])

        let expectation = XCTestExpectation(description: #function)
        mockAsyncQueueDispatcher1.invokedDispatchPersistedCallBack = {
            expectation.fulfill()
        }

        // When
        subject = makeSubject(queue: Queuer.shared)
        subject.start()
        
        // Then
        wait(for: [expectation], timeout: timeout)
        guard let filename = mockPersistor.invokedDeleteFilenameParameter else {
            XCTFail("Sent persisted event was then not deleted")
            return
        }
        XCTAssertEqual(filename, self.filename(with: id))
    }

    // MARK: Private

    private func makeEventTuple(id: UInt, dispatcherId: String? = nil) -> AsyncQueueEventTuple {
        (dispatcherId: dispatcherId ?? dispatcher1ID,
         id: UUID(),
         date: Date(),
         data: data(with: id),
         filename: filename(with: id))
    }

    private func data(with id: UInt) -> Data {
        withUnsafeBytes(of: id) { Data($0) }
    }

    private func filename(with id: UInt) -> String {
        "filename-\(id)"
    }
}
