import Foundation
import Mockable
import Path
import TuistCore
import TuistSupport
import XCTest

@testable import TuistAsyncQueue
@testable import TuistSupportTesting

final class AsyncQueuePersistorTests: TuistUnitTestCase {
    private var subject: AsyncQueuePersistor!
    private var dateService: MockDateServicing!
    private var date = Date(timeIntervalSince1970: 1_725_440_035)

    override func setUp() {
        super.setUp()
        let temporaryDirectory = try! temporaryPath()
        dateService = MockDateServicing()
        subject = AsyncQueuePersistor(
            directory: temporaryDirectory,
            dateService: dateService
        )

        given(dateService)
            .now()
            .willProduce { self.date }
    }

    override func tearDown() {
        dateService = nil
        subject = nil
        super.tearDown()
    }

    func test_write() async throws {
        // Given
        let event = AnyAsyncQueueEvent(
            dispatcherId: "dispatcher",
            date: date
        )

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
        subject = AsyncQueuePersistor(
            directory: temporaryDirectory.appending(try RelativePath(validating: "test/")),
            dateService: dateService
        )

        // Given
        let event = AnyAsyncQueueEvent(
            dispatcherId: "dispatcher",
            date: date
        )

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
        let event = AnyAsyncQueueEvent(
            dispatcherId: "dispatcher",
            date: date
        )
        try subject.write(event: event)
        var persistedEvents = try await subject.readAll()
        XCTAssertEqual(persistedEvents.count, 1)

        // When
        try await subject.delete(event: event)

        // Then
        persistedEvents = try await subject.readAll()
        XCTAssertEqual(persistedEvents.count, 0)
    }

    func test_delete_old_events() async throws {
        // Given
        let event = AnyAsyncQueueEvent(
            dispatcherId: "dispatcher",
            date: date
        )
        try subject.write(event: event)
        var persistedEvents = try await subject.readAll()
        XCTAssertEqual(persistedEvents.count, 1)

        // Moving the clock by over 24 hours
        // Events older than that should get automatically deleted
        date = Date(timeIntervalSince1970: date.timeIntervalSince1970 + 100_005)

        // When
        persistedEvents = try await subject.readAll()

        // Then
        XCTAssertEqual(persistedEvents.count, 0)
    }
}
