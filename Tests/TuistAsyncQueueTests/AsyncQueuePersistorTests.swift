import Foundation
import Path
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
        try subject.write(event: event)

        // Then
        let got = try await subject.readAll()
        let gotEvent = try XCTUnwrap(got.first)
        XCTAssertEqual(gotEvent.dispatcherId, "dispatcher")
        XCTAssertEqual(gotEvent.id, event.id)
        let normalizedDate = Date(timeIntervalSince1970: Double(Int(Double(event.date.timeIntervalSince1970))))
        XCTAssertEqual(gotEvent.date, normalizedDate)
    }

    func test_write_whenDirectoryDoesntExist_itCreatesDirectory() async throws {
        let temporaryDirectory = try! temporaryPath()
        subject = AsyncQueuePersistor(directory: temporaryDirectory.appending(try RelativePath(validating: "test/")))

        // Given
        let event = AnyAsyncQueueEvent(dispatcherId: "dispatcher")

        // When
        try subject.write(event: event)

        // Then
        let got = try await subject.readAll()
        let gotEvent = try XCTUnwrap(got.first)
        XCTAssertEqual(gotEvent.dispatcherId, "dispatcher")
        XCTAssertEqual(gotEvent.id, event.id)
        let normalizedDate = Date(timeIntervalSince1970: Double(Int(Double(event.date.timeIntervalSince1970))))
        XCTAssertEqual(gotEvent.date, normalizedDate)
    }

    func test_delete() async throws {
        // Given
        let event = AnyAsyncQueueEvent(dispatcherId: "dispatcher")
        try subject.write(event: event)
        var persistedEvents = try await subject.readAll()
        XCTAssertEqual(persistedEvents.count, 1)

        // When
        try await subject.delete(event: event)

        // Then
        persistedEvents = try await subject.readAll()
        XCTAssertEqual(persistedEvents.count, 0)
    }
}
