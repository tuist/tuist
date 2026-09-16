import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistCore
import XcodeGraph

@testable import TuistHasher

struct BinaryCacheFingerprintHasherTests {
    @Test func sharedDependencyFingerprintsDoNotDependOnOtherPlatforms() async throws {
        let combined = try await fingerprints(destinations: [.iPhone, .iPad, .macWithiPadDesign, .mac])
        let ios = try await fingerprints(destinations: .iOS)
        let mac = try await fingerprints(destinations: .macOS)
        for name in ["Shared", "Leaf"] {
            #expect(combined[name]?["ios-device"] == ios[name]?["ios-device"])
            #expect(combined[name]?["ios-simulator"] == ios[name]?["ios-simulator"])
            #expect(combined[name]?["macos-device"] == mac[name]?["macos-device"])
            #expect(ios[name]?["macos-device"] == nil)
            #expect(combined[name]?["ios-device"] != nil)
        }
    }

    @Test func dependencyChangesInvalidateConsumerFingerprints() async throws {
        let original = try await fingerprints(destinations: .iOS)
        let changed = try await fingerprints(destinations: .iOS, leafSettings: ["SWIFT_ACTIVE_COMPILATION_CONDITIONS": "CHANGED"])
        #expect(original["Shared"]?["ios-device"] != changed["Shared"]?["ios-device"])
    }

    @Test func deploymentTargetChangesInvalidateExternalFingerprints() async throws {
        let original = try await fingerprints(destinations: .iOS)
        let changed = try await fingerprints(destinations: .iOS, iosVersion: "17.0")
        #expect(original["Shared"]?["ios-device"] != changed["Shared"]?["ios-device"])
    }

    @Test func customDependencyArchitecturesKeepExactHashLookup() async throws {
        let result = try await fingerprints(destinations: .iOS, leafSettings: ["ARCHS": "arm64"])
        #expect(result.isEmpty)
    }

    @Test(.inTemporaryDirectory) func sharesLocalSourceReadsAcrossSDKsAndTheExactHashPass() async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        let source = path.appending(component: "Shared.swift")
        try Data("public struct Shared {}".utf8).write(to: source.url)
        let counting = CountingFileHasher()
        let cached = CachedContentHasher(contentHasher: counting)
        _ = try await cached.hash(path: source)
        let target = Target.test(
            name: "Shared", destinations: [.iPhone, .mac], product: .staticFramework,
            sources: [SourceFile(path: source)]
        )
        let project = Project.test(path: path, targets: [target])
        let graphTarget = GraphTarget(path: path, target: target, project: project)
        let graph = Graph.test(projects: [path: project], dependencies: [.target(name: "Shared", path: path): []])
        let result = try await BinaryCacheFingerprintHasher(contentHasher: cached).fingerprints(
            graph: graph, targets: [graphTarget], additionalStrings: ["Debug"]
        )
        #expect(result[graphTarget]?.count == 3)
        #expect(await counting.reads[source] == 1)
    }

    private func fingerprints(
        destinations: Destinations,
        leafSettings: SettingsDictionary = [:],
        iosVersion: String = "16.0"
    ) async throws -> [String: [String: String]] {
        let path = try AbsolutePath(validating: "/synthetic-package")
        let leaf = Target.test(
            name: "Leaf",
            destinations: destinations,
            product: .staticFramework,
            deploymentTargets: .init(iOS: iosVersion, macOS: "13.0"),
            settings: .test(base: leafSettings)
        )
        let shared = Target.test(
            name: "Shared",
            destinations: destinations,
            product: .staticFramework,
            deploymentTargets: .init(iOS: iosVersion, macOS: "13.0"),
            dependencies: [.target(name: "Leaf")]
        )
        let project = Project.test(path: path, targets: [leaf, shared], type: .external(hash: "fixed-package-revision"))
        let graph = Graph.test(projects: [path: project], dependencies: [
            .target(name: "Shared", path: path): [.target(name: "Leaf", path: path)],
            .target(name: "Leaf", path: path): [],
        ])
        let targets = Set([leaf, shared].map { GraphTarget(path: path, target: $0, project: project) })
        let result = try await BinaryCacheFingerprintHasher().fingerprints(
            graph: graph,
            targets: targets,
            additionalStrings: ["Debug", "test-toolchain", "7"]
        )
        return Dictionary(uniqueKeysWithValues: result.map { ($0.key.target.name, $0.value) })
    }
}

private actor CountingFileHasher: ContentHashing {
    var reads: [AbsolutePath: Int] = [:]
    nonisolated func hash(_ data: Data) throws -> String { ContentHasher().hash(data) }
    nonisolated func hash(_ string: String) throws -> String { try ContentHasher().hash(string) }
    nonisolated func hash(_ boolean: Bool) throws -> String { try ContentHasher().hash(boolean) }
    nonisolated func hash(_ strings: [String]) throws -> String { try ContentHasher().hash(strings) }
    nonisolated func hash(_ dictionary: [String: String]) throws -> String { try ContentHasher().hash(dictionary) }
    func hash(path: AbsolutePath) async throws -> String {
        reads[path, default: 0] += 1
        return try await ContentHasher().hash(path: path)
    }
}
