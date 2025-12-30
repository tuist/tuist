import FileSystem
import Foundation
import Mockable
import Path
import TuistCore
import TuistServer
import TuistSupport
import XCTest

@testable import TuistCacheEE
@testable import TuistTesting

final class CacheLocalStorageIntegrationTests: TuistTestCase {
    private var subject: CacheLocalStorage!
    private var cacheDirectoriesProvider: MockCacheDirectoriesProviding!
    private var artifactSigner: ArtifactSigner!
    private var fileSystem: FileSysteming!

    override func setUp() {
        super.setUp()

        artifactSigner = ArtifactSigner()
        cacheDirectoriesProvider = .init()
        fileSystem = FileSystem()
        subject = CacheLocalStorage(
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            artifactSigner: artifactSigner,
            fileHandler: FileHandler.shared,
            fileSystem: fileSystem
        )
    }

    override func tearDown() {
        subject = nil
        cacheDirectoriesProvider = nil
        artifactSigner = nil
        fileSystem = nil
        super.tearDown()
    }

    func test_fetch_when_a_cached_xcframework_exists_and_is_not_signed() async throws {
        // Given
        let cacheDirectory = try temporaryPath()
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.binaries))
            .willReturn(cacheDirectory)
        let hash = "abcde"
        let hashDirectory = cacheDirectory.appending(component: hash)
        let xcframeworkPath = hashDirectory.appending(component: "framework.xcframework")
        try FileHandler.shared.createFolder(hashDirectory)
        try FileHandler.shared.createFolder(xcframeworkPath)
        let item = CacheStorableItem(name: "ignored", hash: hash)

        // When
        let got = try await subject.fetch([item], cacheCategory: .binaries)

        // Then
        XCTAssertEmpty(got)
    }

    func test_fetch_when_a_cached_xcframework_exists_and_has_a_valid_signature() async throws {
        // Given
        let cacheDirectory = try temporaryPath()
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.binaries))
            .willReturn(cacheDirectory)
        let hash = "abcde"
        let hashDirectory = cacheDirectory.appending(component: hash)
        let xcframeworkPath = hashDirectory.appending(component: "framework.xcframework")
        try await fileSystem.makeDirectory(at: hashDirectory)
        try await fileSystem.makeDirectory(at: xcframeworkPath)
        try artifactSigner.sign(xcframeworkPath)
        let cacheStorableItem = CacheStorableItem(name: "framework", hash: hash)
        let cacheItem: CacheItem = .test(name: "framework", hash: hash, cacheCategory: .binaries)

        // When
        let got = try await subject.fetch([cacheStorableItem], cacheCategory: .binaries)

        // Then
        XCTAssertEqual(got[cacheItem], xcframeworkPath)
    }

    func test_fetch_when_a_cached_xcframework_does_not_exist() async throws {
        // When
        let cacheDirectory = try temporaryPath()
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.binaries))
            .willReturn(cacheDirectory)
        let hash = "abcde"
        let item = CacheStorableItem(name: "ignored", hash: hash)

        let got = try await subject.fetch([item], cacheCategory: .binaries)

        // Then
        XCTAssertEmpty(got)
    }

    func test_fetch_when_a_test_hash_exists() async throws {
        // Given
        let cacheDirectory = try temporaryPath()
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.selectiveTests))
            .willReturn(cacheDirectory)
        let hash = "abcde"
        let hashDirectory = cacheDirectory.appending(components: hash)
        try FileHandler.shared.createFolder(hashDirectory)
        try artifactSigner.sign(hashDirectory)
        let cacheStorableItem = CacheStorableItem(name: "name", hash: hash)
        let cacheItem: CacheItem = .test(name: "name", hash: hash)

        // When
        let got = try await subject.fetch([cacheStorableItem], cacheCategory: .selectiveTests)

        // Then
        XCTAssertEqual(got[cacheItem], hashDirectory)
    }

    func test_fetch_when_a_test_hash_does_not_exist() async throws {
        // When
        let cacheDirectory = try temporaryPath()
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.selectiveTests))
            .willReturn(cacheDirectory)
        let hash = "abcde"
        let item = CacheStorableItem(name: "name", hash: hash)

        let got = try await subject.fetch([item], cacheCategory: .selectiveTests)

        // Then
        XCTAssertEmpty(got)
    }

    func test_store() async throws {
        // Given
        let cacheDirectory = try temporaryPath()
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.binaries))
            .willReturn(cacheDirectory)
        let hash = "abcde"
        let xcframeworkPath = cacheDirectory.appending(component: "framework.xcframework")
        try await fileSystem.makeDirectory(at: xcframeworkPath)
        let item = CacheStorableItem(name: "ignored", hash: hash)

        // When
        _ = try await subject.store([item: [xcframeworkPath]], cacheCategory: .binaries)

        // Then
        let exists = try await fileSystem.exists(
            cacheDirectory.appending(try RelativePath(validating: "\(hash)/framework.xcframework"))
        )
        XCTAssertTrue(exists)
    }
}
