import Foundation
import RxBlocking
import RxSwift
import TuistCore
import TuistSupport
import XCTest
import Queuer

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
        mockAsyncQueueDispatcher1 = MockAsyncQueueDispatcher()
        mockAsyncQueueDispatcher1.stubbedIdentifier = dispatcher1ID
        
        mockAsyncQueueDispatcher2 = MockAsyncQueueDispatcher()
        mockAsyncQueueDispatcher2.stubbedIdentifier = dispatcher2ID
        
        mockCIChecker = MockCIChecker()
        mockPersistor = MockAsyncQueuePersistor()
        mockQueuer = MockQueuer()
        super.setUp()
    }
    
    override func tearDown() {
        super.tearDown()
        mockAsyncQueueDispatcher1 = nil
        mockAsyncQueueDispatcher2 = nil
        mockCIChecker = nil
        mockPersistor = nil
        mockQueuer = nil
        subject = nil
    }
    
    func subjectWithExecutionBlock(
        queue: Queuing? = nil,
        executionBlock: @escaping () throws -> Void = {},
        ciChecker: CIChecking? = nil,
        persistor: AsyncQueuePersisting? = nil,
        dispatchers: [AsyncQueueDispatching]? = nil
    ) -> AsyncQueue {
        guard let asyncQueue = try? AsyncQueue(
            queue: queue ?? mockQueuer,
            executionBlock: executionBlock,
            ciChecker: ciChecker ?? mockCIChecker,
            persistor: persistor ?? mockPersistor,
                dispatchers: dispatchers ?? [mockAsyncQueueDispatcher1, mockAsyncQueueDispatcher2]) else {
            XCTFail("Could not create subject")
            return try! AsyncQueue(dispatchers: [mockAsyncQueueDispatcher1, mockAsyncQueueDispatcher2], executionBlock: executionBlock)
        }
        return asyncQueue
    }
    
    func test_dispatch_eventIsPersisted() throws {
        // Given
        let event = AnyAsyncQueueEvent(dispatcherId: dispatcher1ID)
        subject = subjectWithExecutionBlock()
        
        // When
        subject.dispatch(event: event)
        
        // Then
        guard let persistedEvent = mockPersistor.invokedWriteEvent else {
            XCTFail("Event not passed to the persistor")
            return
        }
        XCTAssertEqual(event.id, persistedEvent.id)
    }
    
    func test_dispatch_eventIsQueued() throws {
        // Given
        let event = AnyAsyncQueueEvent(dispatcherId: dispatcher1ID)
        subject = subjectWithExecutionBlock()
        
        // When
        subject.dispatch(event: event)
        
        // Then
        guard let queuedOperation = mockQueuer.invokedAddOperationParameters?.operation as? ConcurrentOperation else {
            XCTFail("Operation not added to the queuer")
            return
        }
        XCTAssertEqual(queuedOperation.name, event.id.uuidString)
    }
    
    func test_dispatch_eventIsDeletedFromThePersistorOnSendSuccess() throws {
        // Given
        let event = AnyAsyncQueueEvent(dispatcherId: dispatcher1ID)
        subject = subjectWithExecutionBlock(queue: Queuer.shared)
        let expectation = XCTestExpectation(description: #function)
        mockPersistor.invokedDeleteCallBack = {
            expectation.fulfill()
        }

        // When
        subject.dispatch(event: event)
        
        // Then
        wait(for: [expectation], timeout: timeout)
        guard let deletedEvent = mockPersistor.invokedDeleteEvent else {
            XCTFail("Event was not deleted by the persistor")
            return
        }
        XCTAssertEqual(event.id, deletedEvent.id)
    }
    
    func test_dispatch_eventIsDispatchedByTheRightDispatcher() throws {
        // Given
        let event = AnyAsyncQueueEvent(dispatcherId: dispatcher1ID)
        subject = subjectWithExecutionBlock(queue: Queuer.shared)
        let expectation = XCTestExpectation(description: #function)
        mockAsyncQueueDispatcher1.invokedDispatchCallBack = {
            expectation.fulfill()
        }

        // When
        subject.dispatch(event: event)
        
        // Then
        wait(for: [expectation], timeout: timeout)
        guard let dispatchedEvent = mockAsyncQueueDispatcher1.invokedDispatchParameterEvent else {
            XCTFail("Event was not dispatched")
            return
        }
        XCTAssertEqual(event.id, dispatchedEvent.id)
        XCTAssertEqual(mockAsyncQueueDispatcher1.invokedDispatchCount, 1)
        XCTAssertEqual(mockAsyncQueueDispatcher2.invokedDispatchCount, 0)
        XCTAssertNil(mockAsyncQueueDispatcher2.invokedDispatchParameterEvent)
    }
    
    func test_dispatch_queuerTriesThreeTimesToDispatch() throws {
        // Given
        let event = AnyAsyncQueueEvent(dispatcherId: dispatcher1ID)
        subject = subjectWithExecutionBlock(queue: Queuer.shared)
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
        subject.dispatch(event: event)
        
        // Then
        wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(count, 3)
    }
    
    func test_dispatch_doesNotDeleteEventOnError() throws {
        // Given
        let event = AnyAsyncQueueEvent(dispatcherId: dispatcher1ID)
        subject = subjectWithExecutionBlock(queue: Queuer.shared)
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
        subject.dispatch(event: event)
        
        // Then
        wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(count, 3)
        XCTAssertEqual(mockPersistor.invokedDeleteEventCount, 0)
    }

}
