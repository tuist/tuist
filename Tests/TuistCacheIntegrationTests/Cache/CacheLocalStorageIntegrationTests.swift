import Foundation
import RxBlocking
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

    func test_exists_when_a_cached_xcframework_exists() throws {
        // Given
        let config: Config = .test()
        let cacheDirectory = try temporaryPath()
        let hash = "abcde"
        let hashDirectory = cacheDirectory.appending(component: hash)
        let xcframeworkPath = hashDirectory.appending(component: "framework.xcframework")
        try FileHandler.shared.createFolder(hashDirectory)
        try FileHandler.shared.createFolder(xcframeworkPath)

        // When
        let got = try subject.exists(hash: hash, config: config).toBlocking().first()

        // Then
        XCTAssertTrue(got == true)
    }

    func test_exists_when_a_cached_xcframework_does_not_exist() throws {
        // When
        let hash = "abcde"
        let config: Config = .test()

        let got = try subject.exists(hash: hash, config: config).toBlocking().first()

        // Then
        XCTAssertTrue(got == false)
    }

    func test_fetch_when_a_cached_xcframework_exists() throws {
        // Given
        let config: Config = .test()
        let cacheDirectory = try temporaryPath()
        let hash = "abcde"
        let hashDirectory = cacheDirectory.appending(component: hash)
        let xcframeworkPath = hashDirectory.appending(component: "framework.xcframework")
        try FileHandler.shared.createFolder(hashDirectory)
        try FileHandler.shared.createFolder(xcframeworkPath)

        // When
        let got = try subject.fetch(hash: hash, config: config).toBlocking().first()

        // Then
        XCTAssertTrue(got == xcframeworkPath)
    }

    func test_fetch_when_a_cached_xcframework_does_not_exist() throws {
        let hash = "abcde"
        let config: Config = .test()

        XCTAssertThrowsSpecific(try subject.fetch(hash: hash, config: config).toBlocking().first(),
                                CacheLocalStorageError.xcframeworkNotFound(hash: hash))
    }

    func test_store() throws {
        // Given
        let config: Config = .test()
        let hash = "abcde"
        let cacheDirectory = try temporaryPath()
        let xcframeworkPath = cacheDirectory.appending(component: "framework.xcframework")
        try FileHandler.shared.createFolder(xcframeworkPath)

        // When
        _ = try subject.store(hash: hash, config: config, xcframeworkPath: xcframeworkPath).toBlocking().first()

        // Then
        XCTAssertTrue(FileHandler.shared.exists(cacheDirectory.appending(RelativePath("\(hash)/framework.xcframework"))))
    }
}
