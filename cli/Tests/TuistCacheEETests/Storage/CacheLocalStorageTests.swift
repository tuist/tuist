import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistCore
import TuistEnvironment
import TuistEnvironmentTesting
import TuistServer

@testable import TuistCacheEE
@testable import TuistSupport
@testable import TuistTesting

struct CacheLocalStorageErrorTests {
    @Test func type() {
        #expect(CacheLocalStorageError.compiledArtifactNotFound(hash: "hash").type == .abort)
    }

    @Test func description() {
        #expect(
            CacheLocalStorageError.compiledArtifactNotFound(hash: "hash").description
                == "xcframework with hash 'hash' not found in the local cache"
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
    func fetch_whenMacroProductNameDiffersFromTargetNameWithValidSignature() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        let hash = "123"
        let cacheDirectory = temporaryDirectory.appending(component: "cache")
        try await fileSystem.makeDirectory(at: cacheDirectory)

        let cacheDirectoriesProvider = MockCacheDirectoriesProviding()
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.binaries))
            .willReturn(cacheDirectory)

        let hashDirectory = cacheDirectory.appending(component: hash)
        let artifactPath = hashDirectory.appending(component: "MacroProduct.macro")
        try await fileSystem.makeDirectory(at: hashDirectory)
        try await fileSystem.touch(artifactPath)

        let artifactSigner = MockArtifactSigning()
        given(artifactSigner).isValid(.value(artifactPath)).willReturn(true)

        let subject = CacheLocalStorage(
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            artifactSigner: artifactSigner,
            fileSystem: fileSystem
        )

        let got = try await subject.fetch(
            Set([.init(name: "MacroTarget", hash: hash)]), cacheCategory: .binaries
        )

        #expect(got.count == 1)
        let artifact = try #require(got.first)
        #expect(artifact.key.hash == hash)
        #expect(artifact.key.name == "MacroTarget")
        #expect(artifact.value == artifactPath)
    }

    @Test(.inTemporaryDirectory)
    func fetch_whenBundleProductNameReplacesDashWithUnderscore() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        let hash = "123"
        let cacheDirectory = temporaryDirectory.appending(component: "cache")
        try await fileSystem.makeDirectory(at: cacheDirectory)

        let cacheDirectoriesProvider = MockCacheDirectoriesProviding()
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.binaries))
            .willReturn(cacheDirectory)

        let hashDirectory = cacheDirectory.appending(component: hash)
        let artifactPath = hashDirectory.appending(component: "Dash_NamedBundle.bundle")
        try await fileSystem.makeDirectory(at: artifactPath)

        let artifactSigner = MockArtifactSigning()
        given(artifactSigner).isValid(.value(artifactPath)).willReturn(true)

        let subject = CacheLocalStorage(
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            artifactSigner: artifactSigner,
            fileSystem: fileSystem
        )

        let got = try await subject.fetch(
            Set([.init(name: "Dash-NamedBundle", hash: hash)]), cacheCategory: .binaries
        )

        #expect(got.count == 1)
        let artifact = try #require(got.first)
        #expect(artifact.key.hash == hash)
        #expect(artifact.key.name == "Dash-NamedBundle")
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

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func store_evictsLeastRecentlyUsedEntriesToStayWithinTheByteBudget() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let environment = try #require(Environment.mocked)
        environment.variables["TUIST_CACHE_MAX_BYTES"] = "1500000"

        let binariesDirectory = temporaryDirectory.appending(component: "Binaries")
        try await fileSystem.makeDirectory(at: binariesDirectory)
        let staleEntry = binariesDirectory.appending(component: "stale")
        try await fileSystem.makeDirectory(at: staleEntry)
        FileManager.default.createFile(
            atPath: staleEntry.appending(component: "binary").pathString,
            contents: Data(repeating: 0x41, count: 1_000_000)
        )

        let cacheDirectoriesProvider = MockCacheDirectoriesProviding()
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.binaries))
            .willReturn(binariesDirectory)

        let artifact = temporaryDirectory.appending(components: "build", "New.xcframework")
        try await fileSystem.makeDirectory(at: artifact)
        FileManager.default.createFile(
            atPath: artifact.appending(component: "binary").pathString,
            contents: Data(repeating: 0x41, count: 1_000_000)
        )

        let artifactSigner = MockArtifactSigning()
        given(artifactSigner).sign(.any).willReturn()

        let subject = CacheLocalStorage(
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            artifactSigner: artifactSigner,
            fileSystem: fileSystem
        )

        // When: the incoming artifact leaves 0.5 MB of the budget, which the stale entry exceeds.
        let got = try await subject.store(
            [.init(name: "New", hash: "new"): [artifact]],
            cacheCategory: .binaries
        )

        // Then
        #expect(got.count == 1)
        #expect(!(try await fileSystem.exists(staleEntry)))
        #expect(try await fileSystem.exists(binariesDirectory.appending(components: "new", "New.xcframework")))
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func store_admitsOnlyTheArtifactsThatFitTheByteBudget() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let environment = try #require(Environment.mocked)
        environment.variables["TUIST_CACHE_MAX_BYTES"] = "2500000"

        let binariesDirectory = temporaryDirectory.appending(component: "Binaries")
        try await fileSystem.makeDirectory(at: binariesDirectory)
        let cacheDirectoriesProvider = MockCacheDirectoriesProviding()
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.binaries))
            .willReturn(binariesDirectory)

        // Macro artifacts are executables rather than bundles, so this also covers a batch whose
        // size only counts if a regular file measures as itself.
        var items: [CacheStorableItem: [AbsolutePath]] = [:]
        for index in 0 ..< 3 {
            let macro = temporaryDirectory.appending(component: "Target\(index).macro")
            FileManager.default.createFile(
                atPath: macro.pathString,
                contents: Data(repeating: 0x41, count: 1_000_000)
            )
            items[.init(name: "Target\(index)", hash: "hash\(index)")] = [macro]
        }

        let artifactSigner = MockArtifactSigning()
        given(artifactSigner).sign(.any).willReturn()

        let subject = CacheLocalStorage(
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            artifactSigner: artifactSigner,
            fileSystem: fileSystem
        )

        // When: three 1 MB artifacts against the module cache's 2.25 MB share of the 2.5 MB budget.
        let got = try await subject.store(items, cacheCategory: .binaries)

        // Then: the batch is admitted a fitting subset at a time rather than written whole.
        #expect(got.count == 2)
        let entries = try await fileSystem.glob(directory: binariesDirectory, include: ["*"]).collect()
        #expect(entries.count == 2)
    }

    @Test(.inTemporaryDirectory)
    func store_keepsTheRemoteUploadWhenTheLocalCacheIsFull() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        let volume = try TinyVolume.attached()
        defer { volume.detach() }

        let binariesDirectory = volume.mountPoint.appending(component: "Binaries")
        let cacheDirectoriesProvider = MockCacheDirectoriesProviding()
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.binaries))
            .willReturn(binariesDirectory)

        let artifact = temporaryDirectory.appending(components: "build", "Big.xcframework")
        try await fileSystem.makeDirectory(at: artifact)
        FileManager.default.createFile(
            atPath: artifact.appending(component: "binary").pathString,
            contents: Data(repeating: 0x41, count: 5_000_000)
        )

        let artifactSigner = MockArtifactSigning()
        given(artifactSigner).sign(.any).willReturn()

        let subject = CacheLocalStorage(
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            artifactSigner: artifactSigner,
            fileSystem: fileSystem
        )

        // When
        let got = try await subject.store(
            [.init(name: "Big", hash: "hash"): [artifact]],
            cacheCategory: .binaries
        )

        // Then
        #expect(got.isEmpty)
        #expect(!(try await fileSystem.exists(binariesDirectory.appending(component: "hash"))))
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
        let subject = CacheLocalStorage(
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            artifactSigner: MockArtifactSigning(),
            fileSystem: fileSystem
        )
        try await subject.clean()

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
        let subject = CacheLocalStorage(
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            artifactSigner: MockArtifactSigning(),
            fileSystem: fileSystem
        )
        try await subject.clean(maxEntries: 10)

        // Then
        let remaining = try await fileSystem.glob(directory: binariesDirectory, include: ["*"]).collect()
        #expect(remaining.count == 10)
    }

    @Test(.inTemporaryDirectory)
    func clean_evictsLeastRecentlyUsedEntriesPastTheByteBudget() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let binariesDirectory = temporaryDirectory.appending(component: "Binaries")
        try await fileSystem.makeDirectory(at: binariesDirectory)

        let cacheDirectoriesProvider = MockCacheDirectoriesProviding()
        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.binaries))
            .willReturn(binariesDirectory)

        // Three ~1 MB entries, staggered so entry 0 is most recently used.
        for i in 0 ..< 3 {
            let entry = binariesDirectory.appending(component: "hash\(i)")
            let artifact = entry.appending(component: "framework.xcframework")
            try await fileSystem.makeDirectory(at: artifact)
            FileManager.default.createFile(
                atPath: artifact.appending(component: "binary").pathString,
                contents: Data(repeating: 0x41, count: 1_000_000)
            )
            // Set the entry's mtime last, after the file writes bumped it.
            let date = Calendar.current.date(byAdding: .hour, value: -i, to: Date())!
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: entry.pathString)
        }

        // When: a budget that holds ~2 of the 3 entries. LRU keeps the two
        // most-recently-used, evicts the oldest.
        let subject = CacheLocalStorage(
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            artifactSigner: MockArtifactSigning(),
            fileSystem: fileSystem
        )
        try await subject.clean(maxBytes: 2_500_000)

        // Then
        let remaining = try await fileSystem.glob(directory: binariesDirectory, include: ["*"]).collect()
        #expect(remaining.count == 2)
        #expect(try await fileSystem.exists(binariesDirectory.appending(component: "hash0")))
        #expect(try await fileSystem.exists(binariesDirectory.appending(component: "hash1")))
        #expect(!(try await fileSystem.exists(binariesDirectory.appending(component: "hash2"))))
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
        let subject = CacheLocalStorage(
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            artifactSigner: MockArtifactSigning(),
            fileSystem: fileSystem
        )
        try await subject.clean()

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
