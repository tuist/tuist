import Foundation
import TuistGraph
import XCTest

@testable import TuistCache
@testable import TuistCacheTesting
@testable import TuistSupportTesting

final class CacheTests: TuistUnitTestCase {
    var firstCache: MockCacheStorage!
    var secondCache: MockCacheStorage!
    var subject: TuistCache.Cache!

    override func setUp() {
        super.setUp()

        firstCache = MockCacheStorage()
        secondCache = MockCacheStorage()
        subject = Cache(storages: [firstCache, secondCache])
    }

    override func tearDown() {
        firstCache = nil
        secondCache = nil
        subject = nil
        super.tearDown()
    }

    func test_exists_when_in_first_cache_does_not_check_second_and_returns_true() async throws {
        firstCache.existsStub = { name, hash in
            XCTAssertEqual(name, "targetName")
            XCTAssertEqual(hash, "1234")
            return true
        }
        secondCache.existsStub = { _, _ in
            XCTFail("Second cache should not be checked if first hits")
            return false
        }
        let result = try await subject.exists(name: "targetName", hash: "1234")
        XCTAssertTrue(result)
    }

    func test_exists_when_in_second_cache_checks_both_and_returns_true() async throws {
        firstCache.existsStub = { name, hash in
            XCTAssertEqual(name, "targetName")
            XCTAssertEqual(hash, "1234")
            return false
        }
        secondCache.existsStub = { name, hash in
            XCTAssertEqual(name, "targetName")
            XCTAssertEqual(hash, "1234")
            return true
        }
        let result = try await subject.exists(name: "targetName", hash: "1234")
        XCTAssertTrue(result)
    }

    func test_exists_when_not_in_cache_checks_both_and_returns_false() async throws {
        firstCache.existsStub = { name, hash in
            XCTAssertEqual(name, "targetName")
            XCTAssertEqual(hash, "1234")
            return false
        }
        secondCache.existsStub = { name, hash in
            XCTAssertEqual(name, "targetName")
            XCTAssertEqual(hash, "1234")
            return false
        }
        let result = try await subject.exists(name: "targetName", hash: "1234")
        XCTAssertFalse(result)
    }

    func test_fetch_when_in_first_cache_does_not_check_second_and_returns_path() async throws {
        firstCache.fetchStub = { name, hash in
            XCTAssertEqual(name, "targetName")
            XCTAssertEqual(hash, "1234")
            return "/Absolute/Path"
        }
        secondCache.fetchStub = { _, _ in
            XCTFail("Second cache should not be checked if first hits")
            throw TestError("")
        }
        let result = try await subject.fetch(name: "targetName", hash: "1234")
        XCTAssertEqual(result, "/Absolute/Path")
    }

    func test_fetch_when_in_second_cache_checks_both_and_returns_path() async throws {
        firstCache.fetchStub = { name, hash in
            XCTAssertEqual(name, "targetName")
            XCTAssertEqual(hash, "1234")
            throw TestError("")
        }
        secondCache.fetchStub = { name, hash in
            XCTAssertEqual(name, "targetName")
            XCTAssertEqual(hash, "1234")
            return "/Absolute/Path"
        }
        let result = try await subject.fetch(name: "targetName", hash: "1234")
        XCTAssertEqual(result, "/Absolute/Path")
    }

    func test_fetch_when_not_in_cache_checks_both_and_throws() async {
        firstCache.fetchStub = { name, hash in
            XCTAssertEqual(name, "targetName")
            XCTAssertEqual(hash, "1234")
            throw TestError("")
        }
        secondCache.fetchStub = { name, hash in
            XCTAssertEqual(name, "targetName")
            XCTAssertEqual(hash, "1234")
            throw TestError("")
        }
        await XCTAssertThrowsSpecific(
            try await subject.fetch(name: "targetName", hash: "1234"),
            TestError("")
        )
    }
}
