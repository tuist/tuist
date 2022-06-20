import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import XCTest
@testable import TuistCache
@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class CacheLocalStorageIntegrationTests: TuistTestCase {
    var subject: CacheLocalStorage!

    override func setUp() {
        super.setUp()
        let cacheDirectory = try! temporaryPath()
        subject = CacheLocalStorage(cacheDirectory: cacheDirectory)
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_exists_when_a_cached_xcframework_exists() async throws {
        // Given
        let cacheDirectory = try temporaryPath()
        let hash = "abcde"
        let hashDirectory = cacheDirectory.appending(component: hash)
        let xcframeworkPath = hashDirectory.appending(component: "framework.xcframework")
        try FileHandler.shared.createFolder(hashDirectory)
        try FileHandler.shared.createFolder(xcframeworkPath)

        // When
        let got = subject.exists(name: "ignored", hash: hash)

        // Then
        XCTAssertTrue(got)
    }

    func test_exists_when_a_cached_xcframework_does_not_exist() async throws {
        // When
        let hash = "abcde"

        let got = subject.exists(name: "ignored", hash: hash)

        // Then
        XCTAssertFalse(got)
    }

    func test_fetch_when_a_cached_xcframework_exists() async throws {
        // Given
        let cacheDirectory = try temporaryPath()
        let hash = "abcde"
        let hashDirectory = cacheDirectory.appending(component: hash)
        let xcframeworkPath = hashDirectory.appending(component: "framework.xcframework")
        try FileHandler.shared.createFolder(hashDirectory)
        try FileHandler.shared.createFolder(xcframeworkPath)

        // When
        let got = subject.fetch(name: "ignored", hash: hash)

        // Then
        XCTAssertEqual(got, xcframeworkPath)
    }

    func test_fetch_when_a_cached_xcframework_does_not_exist() async throws {
        XCTAssertNil(subject.fetch(name: "ignored", hash: "abcde"))
    }

    func test_store() async throws {
        // Given
        let hash = "abcde"
        let cacheDirectory = try temporaryPath()
        let xcframeworkPath = cacheDirectory.appending(component: "framework.xcframework")
        try FileHandler.shared.createFolder(xcframeworkPath)

        // When
        _ = try subject.store(name: "ignored", hash: hash, paths: [xcframeworkPath])

        // Then
        XCTAssertTrue(FileHandler.shared.exists(cacheDirectory.appending(RelativePath("\(hash)/framework.xcframework"))))
    }
}
