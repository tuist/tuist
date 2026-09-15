import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistCache
import TuistCore
import TuistServer
import XcodeGraph

@testable import TuistCacheEE

struct BinaryCacheStorageTests {
    @Test(.inTemporaryDirectory) func storesOnePayloadAndReusesItForNarrowerRequests() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let storage = PayloadStorage(directory: directory.appending(component: "payloads"))
        let index = LocalBinaryCacheIndex(directory: directory.appending(component: "index"))
        let remoteIndex = LocalBinaryCacheIndex(directory: directory.appending(component: "remote-index"))
        let subject = BinaryCacheStorage(storage: storage, localIndex: index, remoteIndex: remoteIndex)
        let fingerprints = [
            "ios-device": String(repeating: "a", count: 32),
            "ios-simulator": String(repeating: "b", count: 32),
            "macos-device": String(repeating: "c", count: 32),
        ]
        let path = directory.appending(component: "Shared.xcframework")
        try await makeArtifact(at: path, variants: Set(fingerprints.keys))
        let original = CacheStorableItem(
            name: "Shared",
            hash: "combined-hash",
            metadata: .init(binaryCacheFingerprints: fingerprints)
        )
        #expect(try await subject.store([original: [path]], cacheCategory: .binaries) == [original])
        #expect(await storage.storedCount == 1)
        let ios = CacheStorableItem(
            name: "Shared",
            hash: "ios-hash",
            metadata: .init(binaryCacheFingerprints: fingerprints.filter { $0.key != "macos-device" })
        )
        let mac = CacheStorableItem(
            name: "Shared",
            hash: "mac-hash",
            metadata: .init(binaryCacheFingerprints: fingerprints.filter { $0.key == "macos-device" })
        )
        let reader = BinaryCacheStorage(
            storage: storage,
            localIndex: LocalBinaryCacheIndex(directory: directory.appending(component: "empty-reader-index")),
            remoteIndex: remoteIndex
        )
        let fetched = try await reader.fetch([ios, mac], cacheCategory: .binaries)
        #expect(fetched.count == 2)
        #expect(Set(fetched.values).count == 1)
        #expect(await storage.fetchedPayloadCount == 1)
        let fetchedPath = try #require(fetched.values.first)
        try await FileSystem().remove(fetchedPath.appending(components: ["ios-device", "Shared.framework", "Shared"]))
        #expect(try await reader.fetch([ios], cacheCategory: .binaries).isEmpty)
    }

    @Test(.inTemporaryDirectory) func incompleteAndStaleProvidersAreMisses() async throws {
        let directory = try #require(FileSystem.temporaryTestDirectory)
        let storage = PayloadStorage(directory: directory.appending(component: "payloads"))
        let index = LocalBinaryCacheIndex(directory: directory.appending(component: "index"))
        let subject = BinaryCacheStorage(storage: storage, localIndex: index)
        let ios = ["ios-device": String(repeating: "a", count: 32), "ios-simulator": String(repeating: "b", count: 32)]
        let path = directory.appending(component: "Shared.xcframework")
        try await makeArtifact(at: path, variants: Set(ios.keys))
        _ = try await subject.store(
            [CacheStorableItem(name: "Shared", hash: "ios", metadata: .init(binaryCacheFingerprints: ios)): [path]],
            cacheCategory: .binaries
        )
        var combined = ios
        combined["macos-device"] = String(repeating: "c", count: 32)
        let request = CacheStorableItem(name: "Shared", hash: "combined", metadata: .init(binaryCacheFingerprints: combined))
        #expect(try await subject.fetch([request], cacheCategory: .binaries).isEmpty)
        try await FileSystem().remove(directory.appending(component: "payloads"))
        let stale = CacheStorableItem(name: "Shared", hash: "ios", metadata: .init(binaryCacheFingerprints: ios))
        #expect(try await subject.fetch([stale], cacheCategory: .binaries).isEmpty)
    }

    private func makeArtifact(at path: AbsolutePath, variants: Set<String>) async throws {
        let fileSystem = FileSystem()
        try await fileSystem.makeDirectory(at: path)
        let libraries = try BinaryCacheVariant.allCases.filter { variants.contains($0.rawValue) }.map { variant in
            XCFrameworkInfoPlist.Library(
                identifier: variant.rawValue,
                path: try RelativePath(validating: "Shared.framework"),
                mergeable: false,
                platform: variant == .macos ? .macOS : .iOS,
                platformVariant: variant == .iosSimulator ? .simulator : variant == .catalyst ? .maccatalyst : nil,
                architectures: Array(variant.architectures)
            )
        }
        for library in libraries {
            let framework = path.appending(component: library.identifier).appending(library.path)
            try await fileSystem.makeDirectory(at: framework)
            try Data("binary".utf8).write(to: framework.appending(component: "Shared").url)
        }
        try await fileSystem.writeAsPlist(XCFrameworkInfoPlist(libraries: libraries), at: path.appending(component: "Info.plist"))
    }
}

private actor PayloadStorage: CacheStoring {
    let directory: AbsolutePath
    var storedCount = 0
    var fetchedPayloadCount = 0
    init(directory: AbsolutePath) { self.directory = directory }

    func store(
        _ items: [CacheStorableItem: [AbsolutePath]],
        cacheCategory _: RemoteCacheCategory
    ) async throws -> [CacheStorableItem] {
        for (item, paths) in items {
            storedCount += 1
            let folder = directory.appending(component: item.hash)
            try await FileSystem().makeDirectory(at: folder)
            for path in paths {
                try await FileSystem().copy(path, to: folder.appending(component: path.basename))
            }
        }
        return Array(items.keys)
    }

    func fetch(_ items: Set<CacheStorableItem>, cacheCategory: RemoteCacheCategory) async throws -> [CacheItem: AbsolutePath] {
        var result: [CacheItem: AbsolutePath] = [:]
        for item in items {
            let path = directory.appending(components: [item.hash, item.name + ".xcframework"])
            guard try await FileSystem().exists(path) else { continue }
            fetchedPayloadCount += 1
            result[CacheItem(name: item.name, hash: item.hash, source: .remote, cacheCategory: cacheCategory)] = path
        }
        return result
    }
}

struct RemoteBinaryCacheIndexTests {
    @Test func narrowerPublishDoesNotReplaceTheCombinedLookup() async throws {
        let service = IndexService()
        let url = try #require(URL(string: "https://cache.example.com"))
        let subject = RemoteBinaryCacheIndex(
            fullHandle: "test/project",
            cacheURL: url,
            serverURL: url,
            authentication: ServerAuthenticationController(),
            getService: service,
            putService: service
        )
        let ios = String(repeating: "a", count: 32)
        let mac = String(repeating: "b", count: 32)
        let combined = BinaryCacheArtifact(
            name: "Shared", digest: String(repeating: "c", count: 32),
            fingerprints: ["ios-device": ios, "macos-device": mac],
            architectures: [:]
        )
        let narrow = BinaryCacheArtifact(
            name: "Shared", digest: String(repeating: "d", count: 32),
            fingerprints: ["ios-device": ios], architectures: [:]
        )
        try await subject.register([combined])
        try await subject.register([narrow])
        #expect(try await subject.candidates(for: [BinaryCacheArtifact.lookupKey(for: narrow.fingerprints)]) == [narrow])
        #expect(try await subject.candidates(for: [BinaryCacheArtifact.lookupKey(for: combined.fingerprints)]) == [combined])
        #expect(try await subject.candidates(for: [BinaryCacheArtifact.lookupKey(for: ["macos-device": mac])]) == [combined])
    }
}

private actor IndexService: GetCacheValueServicing, PutCacheValueServicing {
    var values: [String: String] = [:]

    func getCacheValue(
        casId: String, fullHandle _: String, serverURL _: URL, authenticationURL _: URL,
        serverAuthenticationController _: ServerAuthenticationControlling
    ) async throws -> KeyValueResponse? {
        values[casId].map { KeyValueResponse(entries: [KeyValueEntry(value: $0)]) }
    }

    func putCacheValue(
        casId: String, entries: [String: String], fullHandle _: String, serverURL _: URL, authenticationURL _: URL,
        serverAuthenticationController _: ServerAuthenticationControlling
    ) async throws {
        values[casId] = entries["value"]
    }
}
