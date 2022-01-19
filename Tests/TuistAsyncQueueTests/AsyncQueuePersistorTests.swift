import Foundation
import RxSwift
import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import TuistAsyncQueue
@testable import TuistSupportTesting

final class AsyncQueuePersistorTests: TuistUnitTestCase {
    var subject: AsyncQueuePersistor!

    override func setUp() {
        super.setUp()
        let temporaryDirectory = try! temporaryPath()
        subject = AsyncQueuePersistor(directory: temporaryDirectory)
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_write() async throws {
        // Given
        let event = AnyAsyncQueueEvent(dispatcherId: "dispatcher")

        // When
        _ = try await subject.write(event: event).value

        // Then
        let got = try await subject.readAll().value
        let gotEvent = try XCTUnwrap(got.first)
        XCTAssertEqual(gotEvent.dispatcherId, "dispatcher")
        XCTAssertEqual(gotEvent.id, event.id)
        let normalizedDate = Date(timeIntervalSince1970: Double(Int(Double(event.date.timeIntervalSince1970))))
        XCTAssertEqual(gotEvent.date, normalizedDate)
    }

    func test_write_whenDirectoryDoesntExist_itCreatesDirectory() async throws {
        let temporaryDirectory = try! temporaryPath()
        subject = AsyncQueuePersistor(directory: temporaryDirectory.appending(RelativePath("test/")))

        // Given
        let event = AnyAsyncQueueEvent(dispatcherId: "dispatcher")

        // When
        _ = try await subject.write(event: event).value

        // Then
        let got = try await subject.readAll().value
        let gotEvent = try XCTUnwrap(got.first)
        XCTAssertEqual(gotEvent.dispatcherId, "dispatcher")
        XCTAssertEqual(gotEvent.id, event.id)
        let normalizedDate = Date(timeIntervalSince1970: Double(Int(Double(event.date.timeIntervalSince1970))))
        XCTAssertEqual(gotEvent.date, normalizedDate)
    }

    func test_delete() async throws {
        // Given
        let event = AnyAsyncQueueEvent(dispatcherId: "dispatcher")
        _ = try await subject.write(event: event).value
        var persistedEvents = try await subject.readAll().value
        XCTAssertEqual(persistedEvents.count, 1)

        // When
        _ = try await subject.delete(event: event).value

        // Then
        persistedEvents = try await subject.readAll().value
        XCTAssertEqual(persistedEvents.count, 0)
    }
}
