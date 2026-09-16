import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import SwiftProtobuf
import Testing
import TuistCache
import TuistCore
import TuistEnvironment
import TuistEnvironmentTesting
import TuistREAPI
import TuistServer
import TuistTesting
import XcodeGraph

@testable import TuistCacheEE

struct BinaryCacheStorageTests {
    private let fingerprints = ["ios-device": "device-inputs", "ios-simulator": "simulator-inputs", "macos-device": "mac-inputs"]

    @Test(.inTemporaryDirectory) func sdkActionsShareBlobsAndNarrowReadersOnlyDownloadTheirSlices() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let remote = MemoryREAPICache()
        let producer = subject(directory.appending(component: "producer"), remote: remote)
        let artifact = directory.appending(component: "Shared.xcframework")
        try await makeArtifact(at: artifact, variants: Set(fingerprints.keys))
        let combined = item("combined", fingerprints)
        #expect(try await producer.store([combined: [artifact]], cacheCategory: .binaries) == [combined])
        #expect(await remote.actions.count == 3)
        let shared = REAPI.digest(Data("shared-resource".utf8))
        #expect(await remote.uploads[shared] == 1)

        let reader = subject(directory.appending(component: "reader"), remote: remote)
        let ios = item("ios", fingerprints.filter { $0.key != "macos-device" })
        let hits = try await reader.fetch([ios], cacheCategory: .binaries)
        let path = try #require(hits.values.first)
        #expect(try await BinaryCacheArtifact.coverage(at: path).keys.sorted() == ["ios-device", "ios-simulator"])
        #expect(await remote.downloads[shared] == 1)
        #expect(await remote.downloads[REAPI.digest(Data("macos-device".utf8))] == nil)
        let count = await remote.downloads
        #expect(try await reader.fetch([ios], cacheCategory: .binaries).values.first == path)
        #expect(await remote.downloads == count)
        #expect(try await reader.fetch([combined], cacheCategory: .binaries).count == 1)
        #expect(await remote.downloads[shared] == 1)
        #expect(await remote.downloads[REAPI.digest(Data("macos-device".utf8))] == 1)
    }

    @Test(.inTemporaryDirectory) func independentlyWarmedSDKsComposeWithoutSubsetRecords() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let remote = MemoryREAPICache()
        let producer = subject(directory.appending(component: "producer"), remote: remote)
        let artifact = directory.appending(component: "Shared.xcframework")
        try await makeArtifact(at: artifact, variants: Set(fingerprints.keys))
        let ios = item("ios", fingerprints.filter { $0.key != "macos-device" })
        _ = try await producer.store([ios: [artifact]], cacheCategory: .binaries)
        let reader = subject(directory.appending(component: "reader"), remote: remote)
        let combined = item("combined", fingerprints)
        #expect(try await reader.fetch([combined], cacheCategory: .binaries).isEmpty)
        let mac = item("mac", fingerprints.filter { $0.key == "macos-device" })
        _ = try await producer.store([mac: [artifact]], cacheCategory: .binaries)
        let hits = try await reader.fetch([combined], cacheCategory: .binaries)
        #expect(hits.count == 1)
        #expect(await remote.actions.count == 3)
        #expect(await remote.uploads.values.allSatisfy { $0 == 1 })
        var changed = fingerprints
        changed["ios-device"] = "changed-compilation-settings"
        #expect(try await reader.fetch([item("changed", changed)], cacheCategory: .binaries).isEmpty)
    }

    @Test(.inTemporaryDirectory) func missingAndCorruptBlobsAreMisses() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let remote = MemoryREAPICache()
        let artifact = directory.appending(component: "Shared.xcframework")
        try await makeArtifact(at: artifact, variants: Set(fingerprints.keys))
        let combined = item("combined", fingerprints)
        _ = try await subject(directory.appending(component: "producer"), remote: remote)
            .store([combined: [artifact]], cacheCategory: .binaries)
        let binary = REAPI.digest(Data("ios-device".utf8))
        await remote.corrupt(binary)
        #expect(try await subject(directory.appending(component: "reader"), remote: remote)
            .fetch([combined], cacheCategory: .binaries).isEmpty)
    }

    @Test(.inTemporaryDirectory) func localOnlyCacheRestoresSlicesAndRepairsMissingMaterialization() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let producer = subject(directory.appending(component: "cache"))
        let artifact = directory.appending(component: "Shared.xcframework")
        try await makeArtifact(at: artifact, variants: Set(fingerprints.keys))
        let combined = item("combined", fingerprints)
        _ = try await producer.store([combined: [artifact]], cacheCategory: .binaries)
        let path = try #require(try await producer.fetch([combined], cacheCategory: .binaries).values.first)
        try await FileSystem().remove(path)
        let freshReader = subject(directory.appending(component: "cache"))
        #expect(try await freshReader.fetch([combined], cacheCategory: .binaries).values.first == path)
    }

    @Test(.inTemporaryDirectory) func failedBlobUploadDoesNotPublishActions() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let remote = MemoryREAPICache()
        await remote.failUploads()
        let artifact = directory.appending(component: "Shared.xcframework")
        try await makeArtifact(at: artifact, variants: Set(fingerprints.keys))
        #expect(try await subject(directory.appending(component: "cache"), remote: remote)
            .store([item("combined", fingerprints): [artifact]], cacheCategory: .binaries).isEmpty)
        #expect(await remote.actions.isEmpty)
    }

    @Test(.inTemporaryDirectory) func preservesSDKSymbolsAndFallsBackForExternalCompanions() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let artifact = directory.appending(component: "Shared.xcframework")
        try await makeArtifact(at: artifact, variants: ["ios-device"])
        let symbols = artifact.appending(components: ["ios-device", "dSYMs", "Shared.framework.dSYM"])
        try await FileSystem().makeDirectory(at: symbols)
        try Data("debug-symbols".utf8).write(to: symbols.appending(component: "DWARF").url)
        let plist = artifact.appending(component: "Info.plist").url
        var info = try #require(PropertyListSerialization
            .propertyList(from: Data(contentsOf: plist), format: nil) as? [String: Any])
        var libraries = try #require(info["AvailableLibraries"] as? [[String: Any]])
        libraries[0]["DebugSymbolsPath"] = "dSYMs"
        info["AvailableLibraries"] = libraries
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: plist)
        let target = item("device", ["ios-device": "device-inputs"])
        let remote = MemoryREAPICache()
        _ = try await subject(directory.appending(component: "producer"), remote: remote)
            .store([target: [artifact]], cacheCategory: .binaries)
        let hit = try #require(try await subject(directory.appending(component: "reader"), remote: remote)
            .fetch([target], cacheCategory: .binaries).values.first)
        #expect(try Data(contentsOf: hit.appending(components: ["ios-device", "dSYMs", "Shared.framework.dSYM", "DWARF"]).url)
            == Data("debug-symbols".utf8))

        let exact = RecordingExactStorage()
        let cache = BinaryCacheStorage(storage: exact, local: BinaryCacheLocalStore(
            directory: directory.appending(component: "fallback"), actionDirectory: directory.appending(component: "actions")
        ), remote: remote)
        let companion = directory.appending(component: "Shared.bundle")
        #expect(try await cache.store([target: [artifact, companion]], cacheCategory: .binaries) == [target])
        #expect(await exact.stored[target] == [artifact, companion])
        #expect(await remote.actions.count == 1)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func blobAdmissionEvictsOldContentAndProtectsResolvedArtifacts() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let environment = try #require(Environment.mocked)
        environment.variables["TUIST_CACHE_MAX_BYTES"] = "1000000"
        let binaries = directory.appending(component: "Binaries")
        let provider = MockCacheDirectoriesProviding()
        given(provider).cacheDirectory(for: .value(.binaries)).willReturn(binaries)
        let local = BinaryCacheLocalStore(
            directory: binaries, actionDirectory: directory.appending(component: "Actions"),
            pruner: BinaryCachePruner(cacheDirectoriesProvider: provider)
        )
        let first = Data(repeating: 1, count: 500_000)
        let second = Data(repeating: 2, count: 500_000)
        let firstDigest = REAPI.digest(first)
        let secondDigest = REAPI.digest(second)
        let source = directory.appending(component: "source").url
        try first.write(to: source)
        try await local.storeBlob(firstDigest, from: source, preserving: [])
        try second.write(to: source)
        await #expect(throws: REAPICacheError.self) {
            try await local.storeBlob(secondDigest, from: source, preserving: [firstDigest.hash])
        }
        #expect(try local.blob(firstDigest) != nil)
        #expect(try local.blob(secondDigest) == nil)
        try await local.storeBlob(secondDigest, from: source, preserving: [])
        #expect(try local.blob(firstDigest) == nil)
        #expect(try local.blob(secondDigest) != nil)
    }

    private func subject(_ path: AbsolutePath, remote: (any REAPICacheStoring)? = nil) -> BinaryCacheStorage {
        BinaryCacheStorage(storage: EmptyCacheStorage(), local: BinaryCacheLocalStore(
            directory: path.appending(component: "Binaries"), actionDirectory: path.appending(component: "Actions")
        ), remote: remote)
    }

    private func item(_ hash: String, _ fingerprints: [String: String]) -> CacheStorableItem {
        CacheStorableItem(name: "Shared", hash: hash, metadata: .init(binaryCacheFingerprints: fingerprints))
    }

    private func makeArtifact(at path: AbsolutePath, variants: Set<String>) async throws {
        let fileSystem = FileSystem()
        try await fileSystem.makeDirectory(at: path)
        let libraries = try BinaryCacheVariant.allCases.filter { variants.contains($0.rawValue) }.map { variant in
            XCFrameworkInfoPlist.Library(
                identifier: variant.rawValue, path: try RelativePath(validating: "Shared.framework"), mergeable: false,
                platform: variant == .macos ? .macOS : .iOS,
                platformVariant: variant == .iosSimulator ? .simulator : variant == .catalyst ? .maccatalyst : nil,
                architectures: Array(variant.architectures)
            )
        }
        for library in libraries {
            let framework = path.appending(component: library.identifier).appending(library.path)
            try await fileSystem.makeDirectory(at: framework)
            try Data(library.identifier.utf8).write(to: framework.appending(component: "Shared").url)
            try Data("shared-resource".utf8).write(to: framework.appending(component: "resource").url)
        }
        try await fileSystem.writeAsPlist(XCFrameworkInfoPlist(libraries: libraries), at: path.appending(component: "Info.plist"))
    }
}

actor MemoryREAPICache: REAPICacheStoring {
    var actions: [REAPI.Digest: REAPI.ActionResult] = [:]
    var blobs: [REAPI.Digest: Data] = [:]
    var uploads: [REAPI.Digest: Int] = [:]
    var downloads: [REAPI.Digest: Int] = [:]
    private var fail = false
    func failUploads() { fail = true }
    func corrupt(_ digest: REAPI.Digest) { blobs[digest] = Data("corrupt".utf8) }
    func actionResult(for digest: REAPI.Digest) async throws -> REAPI.ActionResult? { actions[digest] }
    func storeActionResult(_ result: REAPI.ActionResult, for digest: REAPI.Digest) async throws { actions[digest] = result }
    func uploadBlobs(_ incoming: [REAPI.Digest: URL]) async throws {
        if fail { throw REAPICacheError.corruptBlob }
        for (digest, path) in incoming where blobs[digest] == nil {
            let data = try Data(contentsOf: path)
            #expect(REAPI.digest(data) == digest)
            blobs[digest] = data
            uploads[digest, default: 0] += 1
        }
    }

    func downloadBlob(_ digest: REAPI.Digest, to path: URL) async throws {
        guard let data = blobs[digest] else { throw REAPICacheError.corruptBlob }
        downloads[digest, default: 0] += 1
        try data.write(to: path)
    }
}

private struct EmptyCacheStorage: CacheStoring {
    func fetch(_: Set<CacheStorableItem>, cacheCategory _: RemoteCacheCategory) async throws -> [CacheItem: AbsolutePath] { [:] }
    func store(
        _: [CacheStorableItem: [AbsolutePath]],
        cacheCategory _: RemoteCacheCategory
    ) async throws -> [CacheStorableItem] { [] }
}

private actor RecordingExactStorage: CacheStoring {
    var stored: [CacheStorableItem: [AbsolutePath]] = [:]
    func fetch(_: Set<CacheStorableItem>, cacheCategory _: RemoteCacheCategory) async throws -> [CacheItem: AbsolutePath] { [:] }
    func store(
        _ items: [CacheStorableItem: [AbsolutePath]],
        cacheCategory _: RemoteCacheCategory
    ) async throws -> [CacheStorableItem] {
        stored.merge(items, uniquingKeysWith: { _, new in new })
        return Array(items.keys)
    }
}
