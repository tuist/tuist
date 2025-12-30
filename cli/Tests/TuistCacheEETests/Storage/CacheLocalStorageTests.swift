import FileSystem
import Foundation
import Mockable
import TuistCore
import XCTest

@testable import TuistCacheEE
@testable import TuistSupport
@testable import TuistTesting

final class CacheLocalStorageErrorTests: TuistUnitTestCase {
    func test_type() {
        XCTAssertEqual(CacheLocalStorageError.compiledArtifactNotFound(hash: "hash").type, .abort)
    }

    func test_description() {
        XCTAssertEqual(
            CacheLocalStorageError.compiledArtifactNotFound(hash: "hash").description,
            "xcframework with hash 'hash' not found in the local cache"
        )
    }
}

final class CacheLocalStorageTests: TuistTestCase {
    private var cacheDirectoriesProvider: MockCacheDirectoriesProviding!
    private var artifactSigner: MockArtifactSigning!
    private var fileSystem: FileSysteming!
    private var subject: CacheLocalStorage!

    override func setUp() {
        super.setUp()
        cacheDirectoriesProvider = .init()
        artifactSigner = MockArtifactSigning()
        fileSystem = FileSystem()
        subject = CacheLocalStorage(
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            artifactSigner: artifactSigner,
            fileHandler: fileHandler,
            fileSystem: fileSystem
        )
    }

    override func tearDown() {
        cacheDirectoriesProvider = nil
        artifactSigner = nil
        fileHandler = nil
        fileSystem = nil
        subject = nil
        super.tearDown()
    }

    func test_fetch_when_framework_exists_with_valid_signature() async throws {
        // Given
        let hash = "123"
        let cacheDirectory = try temporaryPath()
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.binaries))
            .willReturn(cacheDirectory)
        let hashDirectory = cacheDirectory.appending(component: hash)
        let artifactPath = hashDirectory.appending(component: "Test.framework")
        try fileHandler.createFolder(artifactPath)
        given(artifactSigner).isValid(.value(artifactPath)).willReturn(true)

        // When
        let got = try await subject.fetch(
            Set([.init(name: "Test", hash: hash)]), cacheCategory: .binaries
        )

        // Then
        XCTAssertEqual(got.count, 1)
        let artifact = try XCTUnwrap(got.first)
        XCTAssertEqual(artifact.key.hash, hash)
        XCTAssertEqual(artifact.key.name, "Test")
        XCTAssertEqual(artifact.value, artifactPath)
    }

    func test_fetch_when_framework_exists_with_invalid_signature() async throws {
        // Given
        let hash = "123"
        let cacheDirectory = try temporaryPath()
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.binaries))
            .willReturn(cacheDirectory)
        let hashDirectory = cacheDirectory.appending(component: hash)
        let artifactPath = hashDirectory.appending(component: "Test.framework")
        try fileHandler.createFolder(artifactPath)
        given(artifactSigner).isValid(.value(artifactPath)).willReturn(false)

        // When
        let got = try await subject.fetch(
            Set([.init(name: "Test", hash: hash)]), cacheCategory: .binaries
        )

        // Then
        XCTAssertEqual(got.count, 0)
    }

    func test_fetch_when_xcframework_exists_with_valid_signature() async throws {
        // Given
        let hash = "123"
        let cacheDirectory = try temporaryPath()
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.binaries))
            .willReturn(cacheDirectory)
        let hashDirectory = cacheDirectory.appending(component: hash)
        let artifactPath = hashDirectory.appending(component: "Test.xcframework")
        try fileHandler.createFolder(artifactPath)
        given(artifactSigner).isValid(.value(artifactPath)).willReturn(true)

        // When
        let got = try await subject.fetch(
            Set([.init(name: "Test", hash: hash)]), cacheCategory: .binaries
        )

        // Then
        XCTAssertEqual(got.count, 1)
        let artifact = try XCTUnwrap(got.first)
        XCTAssertEqual(artifact.key.hash, hash)
        XCTAssertEqual(artifact.key.name, "Test")
        XCTAssertEqual(artifact.value, artifactPath)
    }

    func test_fetch_when_xcframework_exists_with_valid_signature_but_different_name() async throws {
        // Given
        let hash = "123"
        let cacheDirectory = try temporaryPath()
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.binaries))
            .willReturn(cacheDirectory)
        let hashDirectory = cacheDirectory.appending(component: hash)
        let artifactPath = hashDirectory.appending(component: "DifferentName.xcframework")
        try fileHandler.createFolder(artifactPath)
        given(artifactSigner).isValid(.value(artifactPath)).willReturn(true)

        // When
        let got = try await subject.fetch(
            Set([.init(name: "Test", hash: hash)]), cacheCategory: .binaries
        )

        // Then
        XCTAssertEqual(got.count, 0)
    }

    func test_fetch_when_xcframework_exists_with_invalid_signature() async throws {
        // Given
        let hash = "123"
        let cacheDirectory = try temporaryPath()
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.binaries))
            .willReturn(cacheDirectory)
        let hashDirectory = cacheDirectory.appending(component: hash)
        let artifactPath = hashDirectory.appending(component: "Test.xcframework")
        try fileHandler.createFolder(artifactPath)
        given(artifactSigner).isValid(.value(artifactPath)).willReturn(false)

        // When
        let got = try await subject.fetch(
            Set([.init(name: "Test", hash: hash)]), cacheCategory: .binaries
        )

        // Then
        XCTAssertEqual(got.count, 0)
    }

    func test_fetch_when_macro_exists_with_valid_signature() async throws {
        // Given
        let hash = "123"
        let cacheDirectory = try temporaryPath()
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.binaries))
            .willReturn(cacheDirectory)
        let hashDirectory = cacheDirectory.appending(component: hash)
        let artifactPath = hashDirectory.appending(component: "Test.macro")
        try fileHandler.createFolder(artifactPath.parentDirectory)
        try fileHandler.touch(artifactPath)
        given(artifactSigner).isValid(.value(artifactPath)).willReturn(true)

        // When
        let got = try await subject.fetch(
            Set([.init(name: "Test", hash: hash)]), cacheCategory: .binaries
        )

        // Then
        XCTAssertEqual(got.count, 1)
        let artifact = try XCTUnwrap(got.first)
        XCTAssertEqual(artifact.key.hash, hash)
        XCTAssertEqual(artifact.key.name, "Test")
        XCTAssertEqual(artifact.value, artifactPath)
    }

    func test_fetch_when_macro_exists_with_invalid_signature() async throws {
        // Given
        let hash = "123"
        let cacheDirectory = try temporaryPath()
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.binaries))
            .willReturn(cacheDirectory)
        let hashDirectory = cacheDirectory.appending(component: hash)
        let artifactPath = hashDirectory.appending(component: "Test.macro")
        try fileHandler.createFolder(artifactPath.parentDirectory)
        try fileHandler.touch(artifactPath)
        given(artifactSigner).isValid(.value(artifactPath)).willReturn(false)

        // When
        let got = try await subject.fetch(
            Set([.init(name: "Test", hash: hash)]), cacheCategory: .binaries
        )

        // Then
        XCTAssertEqual(got.count, 0)
    }

    func test_store() async throws {
        // Given
        let temporaryDirectory = try temporaryPath()
        let macroInTemporaryDirectoryPath = temporaryDirectory.appending(component: "Test.macro")
        try fileHandler.touch(macroInTemporaryDirectoryPath)

        let hash = "123"
        let cacheDirectory = try temporaryPath()
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.binaries))
            .willReturn(cacheDirectory)
        let hashDirectory = cacheDirectory.appending(component: hash)
        let artifactPath = hashDirectory.appending(component: "Test.macro")
        given(artifactSigner).sign(.value(hashDirectory)).willReturn()
        given(artifactSigner).sign(.value(hashDirectory.appending(component: "Metadata.plist")))
            .willReturn()
        given(artifactSigner).sign(.value(artifactPath)).willReturn()

        // When
        let result = try await subject.store(
            [.init(name: "Test", hash: hash): [macroInTemporaryDirectoryPath]],
            cacheCategory: .binaries
        )

        // Then
        let exists = try await fileSystem.exists(artifactPath)
        XCTAssertTrue(exists)
        verify(artifactSigner).sign(.value(artifactPath)).called(1)

        // Verify return value contains the stored item
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.name, "Test")
        XCTAssertEqual(result.first?.hash, hash)
    }
}
