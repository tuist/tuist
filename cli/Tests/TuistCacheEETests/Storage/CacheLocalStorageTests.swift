import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
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

struct CacheLocalStorageTests {
    private let fileSystem = FileSystem()

    @Test(.inTemporaryDirectory)
    func fetch_whenFrameworkExistsWithValidSignature() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        let hash = "123"
        let cacheDirectory = temporaryDirectory.appending(component: "cache")
        try await fileSystem.makeDirectory(at: cacheDirectory)

        let cacheDirectoriesProvider = MockCacheDirectoriesProviding()
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.binaries))
            .willReturn(cacheDirectory)

        let hashDirectory = cacheDirectory.appending(component: hash)
        let artifactPath = hashDirectory.appending(component: "Test.framework")
        try await fileSystem.makeDirectory(at: artifactPath)

        let artifactSigner = MockArtifactSigning()
        given(artifactSigner).isValid(.value(artifactPath)).willReturn(true)

        let subject = CacheLocalStorage(
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            artifactSigner: artifactSigner,
            fileHandler: FileHandler.shared,
            fileSystem: fileSystem
        )

        // When
        let got = try await subject.fetch(
            Set([.init(name: "Test", hash: hash)]), cacheCategory: .binaries
        )

        // Then
        #expect(got.count == 1)
        let artifact = try #require(got.first)
        #expect(artifact.key.hash == hash)
        #expect(artifact.key.name == "Test")
        #expect(artifact.value == artifactPath)
    }

    @Test(.inTemporaryDirectory)
    func fetch_whenFrameworkExistsWithInvalidSignature() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        let hash = "123"
        let cacheDirectory = temporaryDirectory.appending(component: "cache")
        try await fileSystem.makeDirectory(at: cacheDirectory)

        let cacheDirectoriesProvider = MockCacheDirectoriesProviding()
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.binaries))
            .willReturn(cacheDirectory)

        let hashDirectory = cacheDirectory.appending(component: hash)
        let artifactPath = hashDirectory.appending(component: "Test.framework")
        try await fileSystem.makeDirectory(at: artifactPath)

        let artifactSigner = MockArtifactSigning()
        given(artifactSigner).isValid(.value(artifactPath)).willReturn(false)

        let subject = CacheLocalStorage(
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            artifactSigner: artifactSigner,
            fileHandler: FileHandler.shared,
            fileSystem: fileSystem
        )

        // When
        let got = try await subject.fetch(
            Set([.init(name: "Test", hash: hash)]), cacheCategory: .binaries
        )

        // Then
        #expect(got.count == 0)
    }

    @Test(.inTemporaryDirectory)
    func fetch_whenXcframeworkExistsWithValidSignature() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        let hash = "123"
        let cacheDirectory = temporaryDirectory.appending(component: "cache")
        try await fileSystem.makeDirectory(at: cacheDirectory)

        let cacheDirectoriesProvider = MockCacheDirectoriesProviding()
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.binaries))
            .willReturn(cacheDirectory)

        let hashDirectory = cacheDirectory.appending(component: hash)
        let artifactPath = hashDirectory.appending(component: "Test.xcframework")
        try await fileSystem.makeDirectory(at: artifactPath)

        let artifactSigner = MockArtifactSigning()
        given(artifactSigner).isValid(.value(artifactPath)).willReturn(true)

        let subject = CacheLocalStorage(
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            artifactSigner: artifactSigner,
            fileHandler: FileHandler.shared,
            fileSystem: fileSystem
        )

        // When
        let got = try await subject.fetch(
            Set([.init(name: "Test", hash: hash)]), cacheCategory: .binaries
        )

        // Then
        #expect(got.count == 1)
        let artifact = try #require(got.first)
        #expect(artifact.key.hash == hash)
        #expect(artifact.key.name == "Test")
        #expect(artifact.value == artifactPath)
    }

    @Test(.inTemporaryDirectory)
    func fetch_whenXcframeworkExistsWithValidSignatureButDifferentName() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        let hash = "123"
        let cacheDirectory = temporaryDirectory.appending(component: "cache")
        try await fileSystem.makeDirectory(at: cacheDirectory)

        let cacheDirectoriesProvider = MockCacheDirectoriesProviding()
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.binaries))
            .willReturn(cacheDirectory)

        let hashDirectory = cacheDirectory.appending(component: hash)
        let artifactPath = hashDirectory.appending(component: "DifferentName.xcframework")
        try await fileSystem.makeDirectory(at: artifactPath)

        let artifactSigner = MockArtifactSigning()
        given(artifactSigner).isValid(.value(artifactPath)).willReturn(true)

        let subject = CacheLocalStorage(
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            artifactSigner: artifactSigner,
            fileHandler: FileHandler.shared,
            fileSystem: fileSystem
        )

        // When
        let got = try await subject.fetch(
            Set([.init(name: "Test", hash: hash)]), cacheCategory: .binaries
        )

        // Then
        #expect(got.count == 0)
    }

    @Test(.inTemporaryDirectory)
    func fetch_whenXcframeworkExistsWithInvalidSignature() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        let hash = "123"
        let cacheDirectory = temporaryDirectory.appending(component: "cache")
        try await fileSystem.makeDirectory(at: cacheDirectory)

        let cacheDirectoriesProvider = MockCacheDirectoriesProviding()
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.binaries))
            .willReturn(cacheDirectory)

        let hashDirectory = cacheDirectory.appending(component: hash)
        let artifactPath = hashDirectory.appending(component: "Test.xcframework")
        try await fileSystem.makeDirectory(at: artifactPath)

        let artifactSigner = MockArtifactSigning()
        given(artifactSigner).isValid(.value(artifactPath)).willReturn(false)

        let subject = CacheLocalStorage(
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            artifactSigner: artifactSigner,
            fileHandler: FileHandler.shared,
            fileSystem: fileSystem
        )

        // When
        let got = try await subject.fetch(
            Set([.init(name: "Test", hash: hash)]), cacheCategory: .binaries
        )

        // Then
        #expect(got.count == 0)
    }

    @Test(.inTemporaryDirectory)
    func fetch_whenMacroExistsWithValidSignature() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        let hash = "123"
        let cacheDirectory = temporaryDirectory.appending(component: "cache")
        try await fileSystem.makeDirectory(at: cacheDirectory)

        let cacheDirectoriesProvider = MockCacheDirectoriesProviding()
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.binaries))
            .willReturn(cacheDirectory)

        let hashDirectory = cacheDirectory.appending(component: hash)
        let artifactPath = hashDirectory.appending(component: "Test.macro")
        try await fileSystem.makeDirectory(at: hashDirectory)
        try await fileSystem.touch(artifactPath)

        let artifactSigner = MockArtifactSigning()
        given(artifactSigner).isValid(.value(artifactPath)).willReturn(true)

        let subject = CacheLocalStorage(
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            artifactSigner: artifactSigner,
            fileHandler: FileHandler.shared,
            fileSystem: fileSystem
        )

        // When
        let got = try await subject.fetch(
            Set([.init(name: "Test", hash: hash)]), cacheCategory: .binaries
        )

        // Then
        #expect(got.count == 1)
        let artifact = try #require(got.first)
        #expect(artifact.key.hash == hash)
        #expect(artifact.key.name == "Test")
        #expect(artifact.value == artifactPath)
    }

    @Test(.inTemporaryDirectory)
    func fetch_whenMacroExistsWithInvalidSignature() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        let hash = "123"
        let cacheDirectory = temporaryDirectory.appending(component: "cache")
        try await fileSystem.makeDirectory(at: cacheDirectory)

        let cacheDirectoriesProvider = MockCacheDirectoriesProviding()
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.binaries))
            .willReturn(cacheDirectory)

        let hashDirectory = cacheDirectory.appending(component: hash)
        let artifactPath = hashDirectory.appending(component: "Test.macro")
        try await fileSystem.makeDirectory(at: hashDirectory)
        try await fileSystem.touch(artifactPath)

        let artifactSigner = MockArtifactSigning()
        given(artifactSigner).isValid(.value(artifactPath)).willReturn(false)

        let subject = CacheLocalStorage(
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            artifactSigner: artifactSigner,
            fileHandler: FileHandler.shared,
            fileSystem: fileSystem
        )

        // When
        let got = try await subject.fetch(
            Set([.init(name: "Test", hash: hash)]), cacheCategory: .binaries
        )

        // Then
        #expect(got.count == 0)
    }

    @Test(.inTemporaryDirectory)
    func store() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        let macroInTemporaryDirectoryPath = temporaryDirectory.appending(component: "Test.macro")
        try await fileSystem.touch(macroInTemporaryDirectoryPath)

        let hash = "123"
        let cacheDirectory = temporaryDirectory.appending(component: "cache")
        try await fileSystem.makeDirectory(at: cacheDirectory)

        let cacheDirectoriesProvider = MockCacheDirectoriesProviding()
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.binaries))
            .willReturn(cacheDirectory)

        let hashDirectory = cacheDirectory.appending(component: hash)
        let artifactPath = hashDirectory.appending(component: "Test.macro")

        let artifactSigner = MockArtifactSigning()
        given(artifactSigner).sign(.value(hashDirectory)).willReturn()
        given(artifactSigner).sign(.value(hashDirectory.appending(component: "Metadata.plist")))
            .willReturn()
        given(artifactSigner).sign(.value(artifactPath)).willReturn()

        let subject = CacheLocalStorage(
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            artifactSigner: artifactSigner,
            fileHandler: FileHandler.shared,
            fileSystem: fileSystem
        )

        // When
        let result = try await subject.store(
            [.init(name: "Test", hash: hash): [macroInTemporaryDirectoryPath]],
            cacheCategory: .binaries
        )

        // Then
        let exists = try await fileSystem.exists(artifactPath)
        #expect(exists)
        verify(artifactSigner).sign(.value(artifactPath)).called(1)
        #expect(result.count == 1)
        #expect(result.first?.name == "Test")
        #expect(result.first?.hash == hash)
    }

    @Test(.inTemporaryDirectory)
    func clean_removesOldEntries() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let binariesDirectory = temporaryDirectory.appending(component: "Binaries")
        try await fileSystem.makeDirectory(at: binariesDirectory)

        let cacheDirectoriesProvider = MockCacheDirectoriesProviding()
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.binaries))
            .willReturn(binariesDirectory)

        // Create an old entry (10 days ago)
        let oldEntry = binariesDirectory.appending(component: "oldhash123")
        try await fileSystem.makeDirectory(at: oldEntry)
        let oldDate = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        try FileManager.default.setAttributes(
            [.modificationDate: oldDate],
            ofItemAtPath: oldEntry.pathString
        )

        // Create a recent entry
        let recentEntry = binariesDirectory.appending(component: "recenthash456")
        try await fileSystem.makeDirectory(at: recentEntry)

        // When
        try await CacheLocalStorage.clean(
            fileSystem: fileSystem,
            cacheDirectoriesProvider: cacheDirectoriesProvider
        )

        // Then
        let remaining = try await fileSystem.glob(directory: binariesDirectory, include: ["*"]).collect()
        #expect(remaining.count == 1)
        #expect(remaining.first == recentEntry)
    }

    @Test(.inTemporaryDirectory)
    func clean_limitsMaxEntries() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let binariesDirectory = temporaryDirectory.appending(component: "Binaries")
        try await fileSystem.makeDirectory(at: binariesDirectory)

        let cacheDirectoriesProvider = MockCacheDirectoriesProviding()
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.binaries))
            .willReturn(binariesDirectory)

        // Create 15 entries with staggered modification dates
        for i in 0 ..< 15 {
            let entry = binariesDirectory.appending(component: "hash\(String(format: "%03d", i))")
            try await fileSystem.makeDirectory(at: entry)
            let date = Calendar.current.date(byAdding: .hour, value: -i, to: Date())!
            try FileManager.default.setAttributes(
                [.modificationDate: date],
                ofItemAtPath: entry.pathString
            )
        }

        // When: clean with maxEntries = 10
        try await CacheLocalStorage.clean(
            fileSystem: fileSystem,
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            maxEntries: 10
        )

        // Then
        let remaining = try await fileSystem.glob(directory: binariesDirectory, include: ["*"]).collect()
        #expect(remaining.count == 10)
    }

    @Test(.inTemporaryDirectory)
    func clean_keepsRecentEntries() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let binariesDirectory = temporaryDirectory.appending(component: "Binaries")
        try await fileSystem.makeDirectory(at: binariesDirectory)

        let cacheDirectoriesProvider = MockCacheDirectoriesProviding()
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.binaries))
            .willReturn(binariesDirectory)

        // Create 3 recent entries (all within maxAge)
        for i in 0 ..< 3 {
            let entry = binariesDirectory.appending(component: "hash\(i)")
            try await fileSystem.makeDirectory(at: entry)
            let date = Calendar.current.date(byAdding: .hour, value: -i, to: Date())!
            try FileManager.default.setAttributes(
                [.modificationDate: date],
                ofItemAtPath: entry.pathString
            )
        }

        // When
        try await CacheLocalStorage.clean(
            fileSystem: fileSystem,
            cacheDirectoriesProvider: cacheDirectoriesProvider
        )

        // Then: all 3 should remain
        let remaining = try await fileSystem.glob(directory: binariesDirectory, include: ["*"]).collect()
        #expect(remaining.count == 3)
    }

    @Test(.inTemporaryDirectory)
    func fetch_updatesModificationDate() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let binariesDirectory = temporaryDirectory.appending(component: "Binaries")
        try await fileSystem.makeDirectory(at: binariesDirectory)

        let cacheDirectoriesProvider = MockCacheDirectoriesProviding()
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.binaries))
            .willReturn(binariesDirectory)

        let hash = "testhash"
        let hashDirectory = binariesDirectory.appending(component: hash)
        let artifactPath = hashDirectory.appending(component: "Test.xcframework")
        try await fileSystem.makeDirectory(at: artifactPath)

        let artifactSigner = MockArtifactSigning()
        given(artifactSigner).isValid(.value(artifactPath)).willReturn(true)

        // Set modification date to 2 days ago
        let oldDate = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        try FileManager.default.setAttributes(
            [.modificationDate: oldDate],
            ofItemAtPath: hashDirectory.pathString
        )

        let subject = CacheLocalStorage(
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            artifactSigner: artifactSigner,
            fileHandler: FileHandler.shared,
            fileSystem: fileSystem
        )

        // When
        _ = try await subject.fetch(
            Set([.init(name: "Test", hash: hash)]),
            cacheCategory: .binaries
        )

        // Then: modification date should be updated to approximately now
        let attributes = try FileManager.default.attributesOfItem(atPath: hashDirectory.pathString)
        let modificationDate = try #require(attributes[.modificationDate] as? Date)
        let timeSinceModification = Date().timeIntervalSince(modificationDate)
        #expect(timeSinceModification < 5)
    }
}
