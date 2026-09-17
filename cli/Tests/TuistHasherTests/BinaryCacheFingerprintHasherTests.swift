import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistCore
import TuistThreadSafe
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

    @Test(.inTemporaryDirectory, arguments: [false, true])
    func sharesLocalComponentsAcrossSDKs(reuseExactHash: Bool) async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        let source = path.appending(component: "Shared.swift")
        try Data("public struct Shared {}".utf8).write(to: source.url)
        let counting = CountingFileHasher()
        let cached = CachedContentHasher(contentHasher: counting)
        let target = Target.test(
            name: "Shared", destinations: [.iPhone, .mac], product: .staticFramework,
            settings: .test(base: ["SWIFT_VERSION": "6.0"]),
            sources: [SourceFile(path: source)]
        )
        let project = Project.test(path: path, targets: [target])
        let graphTarget = GraphTarget(path: path, target: target, project: project)
        let graph = Graph.test(projects: [path: project], dependencies: [.target(name: "Shared", path: path): []])
        var exactHashes: [GraphTarget: TargetContentHash] = [:]
        if reuseExactHash {
            exactHashes[graphTarget] = try await TargetContentHasher(contentHasher: cached).contentHash(
                for: graphTarget, hashedTargets: [:], hashedPaths: [:], destination: nil, additionalStrings: ["Debug"]
            )
        }
        let result = try await BinaryCacheFingerprintHasher(contentHasher: cached).fingerprints(
            graph: graph, targets: [graphTarget], additionalStrings: ["Debug"], targetHashes: exactHashes
        )
        #expect(result[graphTarget]?.count == 3)
        #expect(await counting.reads[source] == 1)
        #expect(counting.stringHashes.value["Shared.swift"] == 1)
        let settingsHashes = counting.stringHashes.value.filter { $0.key.hasPrefix("SWIFT_VERSION:") }
        #expect(settingsHashes.values.reduce(0, +) == 1)
    }

    @Test(.inTemporaryDirectory, arguments: [false, true])
    func reusedComponentsMatchFullSDKHashes(external: Bool) async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        let source = path.appending(component: "Shared.swift")
        try Data("public struct Shared {}".utf8).write(to: source.url)
        var target = Target.test(
            name: "Shared", destinations: [.iPhone, .iPad, .macCatalyst, .mac], product: .staticFramework,
            deploymentTargets: .init(iOS: "16.0", macOS: "13.0"),
            infoPlist: .dictionary(["CFBundleName": "Shared"]),
            settings: .test(base: ["SWIFT_VERSION": "6.0"]),
            sources: [SourceFile(path: source, compilerFlags: "-D SHARED")],
            additionalHashingInputs: [.string("generator-v1")],
            dependencies: [.target(name: "Leaf", condition: .when([.ios]))]
        )
        target.buildableFolders = [BuildableFolder(
            path: path, exceptions: BuildableFolderExceptions(exceptions: []),
            resolvedFiles: [BuildableFolderFile(path: source, compilerFlags: "-D FOLDER")]
        )]
        target.foreignBuild = ForeignBuild(
            script: "build-library", inputs: [],
            output: .xcframework(path: path.appending(component: "Shared.xcframework"), linking: .static)
        )
        let project = Project.test(path: path, targets: [target], type: external ? .external(hash: "revision") : .local)
        let graphTarget = GraphTarget(path: path, target: target, project: project)
        let hasher = TargetContentHasher(contentHasher: CachedContentHasher())
        let dependency = GraphHashedTarget(projectPath: path, targetName: "Leaf")
        let exact = try await hasher.contentHash(
            for: graphTarget, hashedTargets: [dependency: "exact-leaf"], hashedPaths: [:], destination: nil,
            embeddedProductReferences: ["Resources.bundle"], additionalStrings: ["Debug"]
        )
        for variant in BinaryCacheVariant.allCases {
            var model = target
            model.destinations = target.destinations.filter { $0.platformFilter == variant.platformFilter }
            model.deploymentTargets = DeploymentTargets(
                iOS: variant.platform == .iOS ? "16.0" : nil,
                macOS: variant.platform == .macOS ? "13.0" : nil
            )
            model.dependencies = target.dependencies.filter {
                $0.condition?.platformFilters.contains(variant.platformFilter) ?? true
            }
            let normalized = GraphTarget(path: path, target: model, project: project)
            let dependencies = [dependency: "leaf-\(variant.rawValue)"]
            let strings = [
                "Debug",
                "xcframework-fingerprint-v1",
                variant.rawValue,
                model.deploymentTargets[variant.platform] ?? "",
            ]
            let full = try await hasher.contentHash(
                for: normalized, hashedTargets: dependencies, hashedPaths: [:], destination: nil,
                embeddedProductReferences: ["Resources.bundle"], additionalStrings: strings
            )
            let reused = try await hasher.fingerprint(
                for: normalized, reusing: exact.subhashes, hashedTargets: dependencies,
                hashedPaths: exact.hashedPaths, additionalStrings: strings
            )
            #expect(reused.hash == full.hash)
            #expect(reused.hash != exact.hash)
        }
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
    nonisolated let stringHashes = ThreadSafe<[String: Int]>([:])
    nonisolated func hash(_ data: Data) throws -> String { ContentHasher().hash(data) }
    nonisolated func hash(_ string: String) throws -> String {
        stringHashes.mutate { $0[string, default: 0] += 1 }
        return try ContentHasher().hash(string)
    }

    nonisolated func hash(_ boolean: Bool) throws -> String { try ContentHasher().hash(boolean) }
    nonisolated func hash(_ strings: [String]) throws -> String { try ContentHasher().hash(strings) }
    nonisolated func hash(_ dictionary: [String: String]) throws -> String { try ContentHasher().hash(dictionary) }
    func hash(path: AbsolutePath) async throws -> String {
        reads[path, default: 0] += 1
        return try await ContentHasher().hash(path: path)
    }
}
