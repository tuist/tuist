import Foundation
import RxBlocking
import RxSwift
import TuistCore
import TuistSupport
import XCTest

@testable import TuistAsyncQueue
@testable import TuistSupportTesting

final class AsyncQueuePersistorTests: TuistUnitTestCase {
    var subject: AsyncQueuePersistor!

    override func setUp() {
        let temporaryDirectory = try! temporaryPath()
        subject = AsyncQueuePersistor(directory: temporaryDirectory)
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
        subject = nil
    }

    func test_write() throws {
        // Given
        let event = AnyAsyncQueueEvent(dispatcherId: "dispatcher")

        // When
        _ = try subject.write(event: event).toBlocking().last()

        // Then
        let got = try subject.readAll().toBlocking().last()
        let gotEvent = try XCTUnwrap(got?.first)
        XCTAssertEqual(gotEvent.dispatcherId, "dispatcher")
        XCTAssertEqual(gotEvent.id, event.id)
        let normalizedDate = Date(timeIntervalSince1970: Double(Int(Double(event.date.timeIntervalSince1970))))
        XCTAssertEqual(gotEvent.date, normalizedDate)
    }

    func test_delete() throws {
        // Given
        let event = AnyAsyncQueueEvent(dispatcherId: "dispatcher")
        _ = try subject.write(event: event).toBlocking().last()
        var persistedEvents = try subject.readAll().toBlocking().last()
        XCTAssertEqual(persistedEvents?.count, 1)

        // When
        _ = try subject.delete(event: event).toBlocking().last()

        // Then
        persistedEvents = try subject.readAll().toBlocking().last()
        XCTAssertEqual(persistedEvents?.count, 0)
    }
}
