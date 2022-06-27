import TSCBasic
import TuistCacheTesting
import TuistCloud
import TuistCore
import TuistGraph
import TuistGraphTesting
import TuistSupport
import XCTest

@testable import TuistCache
@testable import TuistCacheTesting
@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class RetryingCacheStorageTests: TuistUnitTestCase {
    var subject: RetryingCacheStorage!
    var storage: MockCacheStorage!

    override func setUpWithError() throws {
        try super.setUpWithError()

        storage = MockCacheStorage()
        subject = RetryingCacheStorage(cacheStoring: storage)
    }

    override func tearDown() {
        subject = nil
        storage = nil
        super.tearDown()
    }

    // - exists

    func test_exists_whenSucceeds_doesNotRetry() async throws {
        var existsCalls = 0
        // Given
        storage.existsStub = { _, _ in
            existsCalls += 1
            return true
        }

        // When
        let result = try await subject.exists(name: "targetName", hash: "acho tio")
        XCTAssertEqual(existsCalls, 1)
        XCTAssertTrue(result)
    }

    func test_exists_whenFails_retries() async throws {
        var existsCalls = 0
        // Given
        storage.existsStub = { _, _ in
            existsCalls += 1
            if existsCalls == 1 {
                throw TestError("exists failed")
            } else {
                return true
            }
        }

        // When
        let result = try await subject.exists(name: "targetName", hash: "acho tio")
        XCTAssertEqual(existsCalls, 2)
        XCTAssertTrue(result)
    }

    func test_exists_whenFailsTwice_throws() async throws {
        let error = TestError("exists failed")
        var existsCalls = 0
        // Given
        storage.existsStub = { _, _ in
            existsCalls += 1
            throw error
        }

        // When
        await XCTAssertThrowsSpecific(
            try await subject.exists(name: "targetName", hash: "acho tio"),
            error
        )
        XCTAssertEqual(existsCalls, 2)
    }

    // - fetch

    func test_fetch_whenSucceeds_doesNotRetry() async throws {
        var fetchCalls = 0
        // Given
        storage.fetchStub = { _, _ in
            fetchCalls += 1
            return "/"
        }

        // When
        let result = try await subject.fetch(name: "targetName", hash: "acho tio")
        XCTAssertEqual(fetchCalls, 1)
        XCTAssertEqual(result, "/")
    }

    func test_fetch_whenFails_retries() async throws {
        var fetchCalls = 0
        // Given
        storage.fetchStub = { _, _ in
            fetchCalls += 1
            if fetchCalls == 1 {
                throw TestError("fetch failed")
            } else {
                return "/"
            }
        }

        // When
        let result = try await subject.fetch(name: "targetName", hash: "acho tio")
        XCTAssertEqual(fetchCalls, 2)
        XCTAssertEqual(result, "/")
    }

    func test_fetch_whenFailsTwice_throws() async throws {
        let error = TestError("fetch failed")
        var fetchCalls = 0
        // Given
        storage.fetchStub = { _, _ in
            fetchCalls += 1
            throw error
        }

        // When
        await XCTAssertThrowsSpecific(
            try await subject.fetch(name: "targetName", hash: "acho tio"),
            error
        )
        XCTAssertEqual(fetchCalls, 2)
    }

    // - store

    func test_store_whenSucceeds_doesNotRetry() async throws {
        var storeCalls = 0
        // Given
        storage.storeStub = { _, _, _ in
            storeCalls += 1
        }

        // When
        try await subject.store(name: "targetName", hash: "acho tio", paths: [])
        XCTAssertEqual(storeCalls, 1)
    }

    func test_store_whenFails_retries() async throws {
        var storeCalls = 0
        // Given
        storage.storeStub = { _, _, _ in
            storeCalls += 1
            if storeCalls == 1 {
                throw TestError("store failed")
            }
        }

        // When
        try await subject.store(name: "targetName", hash: "acho tio", paths: [])
        XCTAssertEqual(storeCalls, 2)
    }

    func test_store_whenFailsTwice_throws() async throws {
        let error = TestError("store failed")
        var storeCalls = 0
        // Given
        storage.storeStub = { _, _, _ in
            storeCalls += 1
            throw error
        }

        // When
        await XCTAssertThrowsSpecific(
            try await subject.store(name: "targetName", hash: "acho tio", paths: []),
            error
        )
        XCTAssertEqual(storeCalls, 2)
    }
}
