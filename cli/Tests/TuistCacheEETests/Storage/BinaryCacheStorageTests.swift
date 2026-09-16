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
        #expect(try await XCFrameworkCoverage.read(at: path).keys.sorted() == ["ios-device", "ios-simulator"])
        #expect(await remote.downloads[shared] == 1)
        let exact = try BinaryCacheAction(name: ios.name, targetHash: ios.hash)
        #expect(await remote.queries[exact.digest] == nil)
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

    @Test(.inTemporaryDirectory) func preservesSDKSymbolsAndStoresExternalCompanionsInExactREAPITree() async throws {
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

        let exactRemote = MemoryREAPICache()
        let companion = directory.appending(component: "Shared.bundle")
        try await FileSystem().makeDirectory(at: companion)
        try Data("companion".utf8).write(to: companion.appending(component: "resource").url)
        let cache = subject(directory.appending(component: "exact-producer"), remote: exactRemote)
        #expect(try await cache.store([target: [artifact, companion]], cacheCategory: .binaries) == [target])
        #expect(await exactRemote.actions.count == 1)
        let reader = subject(directory.appending(component: "exact-reader"), remote: exactRemote)
        let restored = try #require(try await reader.fetch([target], cacheCategory: .binaries).values.first)
        #expect(restored.extension == "xcframework")
        #expect(try Data(contentsOf: restored.parentDirectory.appending(components: ["Shared.bundle", "resource"]).url)
            == Data("companion".utf8))
        #expect(try await reader.fetch([item("changed", target.metadata.binaryCacheFingerprints)], cacheCategory: .binaries)
            .isEmpty)
    }

    @Test(.inTemporaryDirectory, arguments: ["bundle", "macro", "framework"])
    func exactProductsRoundTripAndRepairLocally(product: String) async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let remote = MemoryREAPICache()
        let artifact = directory.appending(component: "Shared." + product)
        if product == "macro" {
            try Data("#!/bin/sh\necho macro\n".utf8).write(to: artifact.url)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: artifact.pathString)
        } else {
            try await FileSystem().makeDirectory(at: artifact)
            try Data("payload".utf8).write(to: artifact.appending(component: "contents").url)
            try FileManager.default.createSymbolicLink(
                atPath: artifact.appending(component: "link").pathString,
                withDestinationPath: "contents"
            )
        }
        let target = item("exact", [:])
        _ = try await subject(directory.appending(component: "producer"), remote: remote)
            .store([target: [artifact]], cacheCategory: .binaries)
        #expect(await remote.actions.count == 1)
        let path = directory.appending(component: "reader")
        let reader = subject(path, remote: remote)
        let restored = try #require(try await reader.fetch([target], cacheCategory: .binaries).values.first)
        #expect(restored.extension == product)
        if product == "macro" {
            #expect(FileManager.default.isExecutableFile(atPath: restored.pathString))
            #expect(try Data(contentsOf: restored.url) == Data(contentsOf: artifact.url))
        } else {
            #expect(try Data(contentsOf: restored.appending(component: "link").url) == Data("payload".utf8))
        }
        try FileManager.default.removeItem(at: restored.url)
        #expect(try await subject(path).fetch([target], cacheCategory: .binaries).values.first == restored)
        #expect(try await reader.fetch([item("changed", [:])], cacheCategory: .binaries).isEmpty)
    }

    @Test(.inTemporaryDirectory) func unsupportedArchitectureUsesExactTargetAction() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let artifact = directory.appending(component: "Shared.xcframework")
        try await makeArtifact(at: artifact, variants: ["ios-simulator"])
        let plist = artifact.appending(component: "Info.plist").url
        var info = try #require(PropertyListSerialization
            .propertyList(from: Data(contentsOf: plist), format: nil) as? [String: Any])
        var libraries = try #require(info["AvailableLibraries"] as? [[String: Any]])
        libraries[0]["SupportedArchitectures"] = ["arm64"]
        info["AvailableLibraries"] = libraries
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: plist)
        let remote = MemoryREAPICache()
        let target = item("custom-architectures", ["ios-simulator": "simulator-inputs"])
        _ = try await subject(directory.appending(component: "producer"), remote: remote)
            .store([target: [artifact]], cacheCategory: .binaries)
        let exact = try BinaryCacheAction(name: target.name, targetHash: target.hash)
        #expect(await remote.actions[exact.digest]?.outputDirectories.first?.path == "outputs")
        let reader = subject(directory.appending(component: "reader"), remote: remote)
        let restored = try #require(try await reader.fetch([target], cacheCategory: .binaries).values.first)
        #expect(try await XCFrameworkCoverage.read(at: restored)["ios-simulator"] == ["arm64"])
        #expect(try await reader.fetch([item("other", target.metadata.binaryCacheFingerprints)], cacheCategory: .binaries)
            .isEmpty)
    }

    @Test(.inTemporaryDirectory) func selectiveTestsKeepTheirExistingStorage() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let delegate = RecordingSelectiveTestsStorage()
        let cache = BinaryCacheStorage(selectiveTestsStorage: delegate, local: BinaryCacheLocalStore(
            directory: directory.appending(component: "Binaries")
        ))
        let target = item("tests", [:])
        #expect(try await cache.store([target: []], cacheCategory: .selectiveTests) == [target])
        _ = try await cache.fetch([target], cacheCategory: .selectiveTests, preserving: ["protected"])
        #expect(await delegate.categories == [.selectiveTests, .selectiveTests])
        #expect(await delegate.preserved == ["protected"])
        #expect(try await cache.fetch([target], cacheCategory: .binaries).isEmpty)
        #expect(await delegate.categories.count == 2)
    }

    @Test(.inTemporaryDirectory) func corruptExactOutputIsAMissWithoutOldStorageFallback() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let remote = MemoryREAPICache()
        let artifact = directory.appending(component: "Shared.macro")
        let data = Data("macro executable".utf8)
        try data.write(to: artifact.url)
        let target = item("macro", [:])
        _ = try await subject(directory.appending(component: "producer"), remote: remote)
            .store([target: [artifact]], cacheCategory: .binaries)
        await remote.corrupt(REAPI.digest(data))
        #expect(try await subject(directory.appending(component: "reader"), remote: remote)
            .fetch([target], cacheCategory: .binaries).isEmpty)
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
            directory: binaries,
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

    @Test(.inTemporaryDirectory) func thousandTargetMissesAreBoundedAndQueriedOnlyOnce() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let remote = MemoryREAPICache()
        await remote.delayLookups()
        let targets = Set((0 ..< 1000).map { item("target-\($0)", ["ios-device": "sdk-\($0)"]) })
        #expect(try await subject(directory, remote: remote).fetch(targets, cacheCategory: .binaries).isEmpty)
        #expect(await remote.queries.count == 2000)
        #expect(await remote.queries.values.allSatisfy { $0 == 1 })
        #expect(await remote.maximumActiveLookups > 1)
        #expect(await remote.maximumActiveLookups <= 32)
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func actionRecordsShareTheBinaryBudgetAndPruning() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        Environment.mocked?.variables["TUIST_CACHE_MAX_BYTES"] = "100000"
        let binaries = directory.appending(component: "Binaries")
        let provider = MockCacheDirectoriesProviding()
        given(provider).cacheDirectory(for: .value(.binaries)).willReturn(binaries)
        let pruner = BinaryCachePruner(cacheDirectoriesProvider: provider)
        let local = BinaryCacheLocalStore(directory: binaries, pruner: pruner)
        let payload = Data(repeating: 1, count: 10000)
        let digest = REAPI.digest(payload)
        let result = REAPI.ActionResult.with {
            $0.outputDirectories = [.with { $0.path = String(repeating: "x", count: 60000) }]
        }
        let source = directory.appending(component: "blob").url
        try payload.write(to: source)
        let admission = try await local.admission(preserving: [])
        try await local.storeBlob(digest, from: source, preserving: [], admission: admission)
        try await local.storeAction(result, digest: digest, preserving: [digest.hash], admission: admission)
        try await local.storeAction(result, digest: digest, preserving: [digest.hash], admission: admission)
        #expect(try local.action(digest) == result)
        #expect(try local.blob(digest) != nil)
        #expect(FileManager.default.fileExists(atPath: binaries.appending(components: [
            "action-\(digest.hash)", "result.pb",
        ]).pathString))
        let remaining = try #require(try await pruner.headroom())
        let resultSize = try result.serializedData().count
        #expect(remaining == 90000 - payload.count - resultSize)
        #expect(await admission.admit(remaining))
        #expect(await admission.admit(1) == false)
        try await pruner.clean(maxBytes: payload.count, minimumEntries: 0, preserving: [digest.hash])
        #expect(try local.action(digest) == nil)
        #expect(try local.blob(digest) != nil)
    }

    @Test(.inTemporaryDirectory) func invalidTargetAndPartialUploadDoNotDiscardHealthyTargets() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let good = directory.appending(component: "CustomProduct.macro")
        let failed = directory.appending(component: "Failed.macro")
        try Data("good".utf8).write(to: good.url)
        try Data("failed".utf8).write(to: failed.url)
        let remote = MemoryREAPICache()
        await remote.failUpload(REAPI.digest(Data("failed".utf8)))
        let healthy = item("good", [:])
        let result = try await subject(directory.appending(component: "producer"), remote: remote).store([
            healthy: [good], item("failed", [:]): [failed],
            item("invalid", [:]): [directory.appending(component: "missing.bundle")],
        ], cacheCategory: .binaries)
        #expect(result == [healthy])
        #expect(await remote.actions.count == 1)
        let restored = try #require(try await subject(directory.appending(component: "reader"), remote: remote)
            .fetch([healthy], cacheCategory: .binaries).values.first)
        #expect(restored.basename == "CustomProduct.macro")
        #expect(try Data(contentsOf: restored.url) == Data("good".utf8))
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func tightBudgetRetainsMaterializationWithoutKeepingDuplicateCASPayload() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        Environment.mocked?.variables["TUIST_CACHE_MAX_BYTES"] = "100000"
        let binaries = directory.appending(component: "Binaries")
        let provider = MockCacheDirectoriesProviding()
        given(provider).cacheDirectory(for: .value(.binaries)).willReturn(binaries)
        let local = BinaryCacheLocalStore(
            directory: binaries,
            pruner: BinaryCachePruner(cacheDirectoriesProvider: provider)
        )
        let remote = MemoryREAPICache()
        let cache = BinaryCacheStorage(selectiveTestsStorage: EmptyCacheStorage(), local: local, remote: remote)
        let path = directory.appending(component: "Shared.macro")
        let body = Data(repeating: 42, count: 60000)
        try body.write(to: path.url)
        let target = item("budget", [:])
        #expect(try await cache.store([target: [path]], cacheCategory: .binaries) == [target])
        #expect(try local.blob(REAPI.digest(body)) == nil)
        let restored = try #require(try await cache.fetch([target], cacheCategory: .binaries).values.first)
        #expect(try Data(contentsOf: restored.url) == body)
        #expect(await remote.downloads.isEmpty)
        let fresh = BinaryCacheStorage(selectiveTestsStorage: EmptyCacheStorage(), local: local, remote: remote)
        #expect(try await fresh.fetch([target], cacheCategory: .binaries).values.first == restored)
        #expect(await remote.downloads.isEmpty)
    }

    @Test(.inTemporaryDirectory) func overlappingFetchOperationsShareOneLocalAdmissionAndCAS() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let remote = MemoryREAPICache()
        let artifact = directory.appending(component: "Shared.xcframework")
        try await makeArtifact(at: artifact, variants: Set(fingerprints.keys))
        _ = try await subject(directory.appending(component: "producer"), remote: remote)
            .store([item("combined", fingerprints): [artifact]], cacheCategory: .binaries)
        let reader = subject(directory.appending(component: "reader"), remote: remote)
        async let ios = reader.fetch([item("ios", fingerprints.filter { $0.key != "macos-device" })], cacheCategory: .binaries)
        async let mac = reader.fetch([item("mac", fingerprints.filter { $0.key == "macos-device" })], cacheCategory: .binaries)
        let hits = try await (ios, mac)
        #expect(hits.0.count == 1)
        #expect(hits.1.count == 1)
        #expect(await remote.downloads[REAPI.digest(Data("shared-resource".utf8))] == 1)
    }

    private func subject(_ path: AbsolutePath, remote: (any REAPICacheStoring)? = nil) -> BinaryCacheStorage {
        BinaryCacheStorage(selectiveTestsStorage: EmptyCacheStorage(), local: BinaryCacheLocalStore(
            directory: path.appending(component: "Binaries")
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
    var queries: [REAPI.Digest: Int] = [:]
    var maximumActiveLookups = 0
    private var activeLookups = 0
    private var delayed = false
    private var rejected: Set<REAPI.Digest> = []
    func delayLookups() { delayed = true }
    func failUpload(_ digest: REAPI.Digest) { rejected.insert(digest) }
    private var fail = false
    func failUploads() { fail = true }
    func corrupt(_ digest: REAPI.Digest) { blobs[digest] = Data("corrupt".utf8) }
    func actionResult(for digest: REAPI.Digest) async throws -> REAPI.ActionResult? {
        queries[digest, default: 0] += 1
        activeLookups += 1
        maximumActiveLookups = max(maximumActiveLookups, activeLookups)
        defer { activeLookups -= 1 }
        if delayed { try await Task.sleep(for: .milliseconds(2)) }
        return actions[digest]
    }

    func uploadAvailableBlobs(_ incoming: [REAPI.Digest: URL]) async throws -> Set<REAPI.Digest> {
        let accepted = incoming.filter { !rejected.contains($0.key) }
        try await uploadBlobs(accepted)
        return Set(accepted.keys)
    }

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
    func fetch(_: Set<CacheStorableItem>, cacheCategory: RemoteCacheCategory) async throws -> [CacheItem: AbsolutePath] {
        #expect(cacheCategory != .binaries)
        return [:]
    }

    func store(
        _: [CacheStorableItem: [AbsolutePath]],
        cacheCategory: RemoteCacheCategory
    ) async throws -> [CacheStorableItem] {
        #expect(cacheCategory != .binaries)
        return []
    }
}

private actor RecordingSelectiveTestsStorage: CacheStoring {
    var categories: [RemoteCacheCategory] = []
    var preserved: Set<String> = []
    func fetch(_ items: Set<CacheStorableItem>, cacheCategory: RemoteCacheCategory) async throws -> [CacheItem: AbsolutePath] {
        try await fetch(items, cacheCategory: cacheCategory, preserving: [])
    }

    func fetch(
        _: Set<CacheStorableItem>,
        cacheCategory: RemoteCacheCategory,
        preserving: Set<String>
    ) async throws -> [CacheItem: AbsolutePath] {
        categories.append(cacheCategory)
        preserved = preserving
        return [:]
    }

    func store(
        _ items: [CacheStorableItem: [AbsolutePath]],
        cacheCategory: RemoteCacheCategory
    ) async throws -> [CacheStorableItem] {
        categories.append(cacheCategory)
        return Array(items.keys)
    }
}
