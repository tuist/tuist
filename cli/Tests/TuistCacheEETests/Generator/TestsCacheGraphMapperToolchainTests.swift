import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistCache
import TuistCore
import TuistHasher
import TuistServer
import TuistSupport
import XcodeGraph

@testable import TuistCacheEE

struct TestsCacheGraphMapperToolchainTests {
    @Test(.inTemporaryDirectory) func map_hashesTestTargetsDifferently_whenTheToolchainChanges() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let frameworkTarget = Target.test(name: "Framework", product: .framework)
        let unitTestsTarget = Target.test(
            name: "FrameworkTests",
            product: .unitTests,
            dependencies: [.target(name: "Framework")]
        )
        let project = Project.test(path: temporaryDirectory, targets: [frameworkTarget, unitTestsTarget])
        let graph = Graph.test(
            path: temporaryDirectory,
            projects: [project.path: project],
            dependencies: [
                .target(name: "FrameworkTests", path: project.path): [
                    .target(name: "Framework", path: project.path),
                ],
            ]
        )

        // When
        let oldToolchainHashes = try await targetTestHashes(for: graph, swiftlangVersion: "6.3.2.1.108")
        let oldToolchainRerunHashes = try await targetTestHashes(for: graph, swiftlangVersion: "6.3.2.1.108")
        let newToolchainHashes = try await targetTestHashes(for: graph, swiftlangVersion: "6.4.0.1.2")

        // Then
        let oldToolchainTestHash = try #require(oldToolchainHashes[project.path]?["FrameworkTests"])
        let newToolchainTestHash = try #require(newToolchainHashes[project.path]?["FrameworkTests"])
        #expect(oldToolchainHashes == oldToolchainRerunHashes)
        #expect(oldToolchainTestHash != newToolchainTestHash)
    }

    private func targetTestHashes(
        for graph: Graph,
        swiftlangVersion: String
    ) async throws -> [AbsolutePath: [String: String]] {
        let swiftVersionProvider = MockSwiftVersionProviding()
        given(swiftVersionProvider).swiftlangVersion().willReturn(swiftlangVersion)
        let cacheStorage = MockCacheStoring()
        given(cacheStorage).fetch(.any, cacheCategory: .any).willReturn([:])
        let subject = TestsCacheGraphMapper(
            testPlan: nil,
            includedTargets: [],
            excludedTargets: [],
            graphContentHasher: GraphContentHasher(contentHasher: ContentHasher()),
            cacheStorage: cacheStorage,
            cacheDirectoriesProvider: CacheDirectoriesProvider(),
            ignoreSelectiveTesting: false,
            destination: nil
        )

        let (_, _, environment) = try await SwiftVersionProvider.$current.withValue(swiftVersionProvider) {
            try await subject.map(graph: graph, environment: MapperEnvironment())
        }
        return environment.targetTestHashes
    }
}
