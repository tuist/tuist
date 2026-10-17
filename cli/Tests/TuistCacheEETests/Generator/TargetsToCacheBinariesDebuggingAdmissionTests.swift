import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistCache
import TuistConfig
import TuistCore
import TuistHasher
import TuistServer
import XcodeGraph
@testable import TuistCacheEE

struct TargetsToCacheBinariesDebuggingAdmissionTests {
    @Test(.inTemporaryDirectory, arguments: ["verified", "missing", "invalid"])
    func replacementRequiresVerifiedMetadata(status: String) async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        let fixture = fixture(at: path, coverage: false)
        let artifact = path.appending(component: "Feature.xcframework")
        let reader = MockCachedModuleDebuggingMetadataReading()
        let mappings = [DebuggerSourceMapping(
            original: try AbsolutePath(validating: "/producer/Feature.swift"),
            current: path.appending(component: "Feature.swift")
        )]
        if status == "invalid" {
            given(reader).sourceMappings(artifact: .any, target: .any).willThrow(NSError(domain: "invalid-metadata", code: 1))
        } else {
            given(reader).sourceMappings(artifact: .any, target: .any).willReturn(status == "verified" ? mappings : nil)
        }
        let storage = MockCacheStoring()
        given(storage).fetch(.any, cacheCategory: .value(.binaries)).willReturn([.test(
            name: "Feature",
            hash: "feature"
        ): artifact])
        let mutator = MockCacheGraphMutating()
        given(mutator).map(graph: .any, precompiledArtifacts: .any, sources: .any, keepSourceTargets: .any)
            .willReturn(fixture.graph)
        let subject = subject(fixture: fixture, path: path, storage: storage, mutator: mutator, reader: reader)
        let (_, _, environment) = try await subject.map(graph: fixture.graph, environment: MapperEnvironment())
        verify(mutator).map(
            graph: .any,
            precompiledArtifacts: .value(status == "verified" ? [fixture.feature: artifact] : [:]),
            sources: .any,
            keepSourceTargets: .any
        ).called(1)
        #expect(environment.cachedModuleSourceMappings == (status == "verified" ? [artifact: mappings] : [:]))
    }

    @Test(.inTemporaryDirectory, arguments: [false, true])
    func coverageCannotAdmitOrdinaryPrecomputedHashes(coverage: Bool) async throws {
        let path = try #require(FileSystem.temporaryTestDirectory)
        let fixture = fixture(at: path, coverage: coverage)
        let storage = MockCacheStoring()
        given(storage).fetch(.any, cacheCategory: .value(.binaries)).willReturn([:])
        let mutator = MockCacheGraphMutating()
        given(mutator).map(graph: .any, precompiledArtifacts: .any, sources: .any, keepSourceTargets: .any)
            .willReturn(fixture.graph)
        let reader = MockCachedModuleDebuggingMetadataReading()
        _ = try await subject(fixture: fixture, path: path, storage: storage, mutator: mutator, reader: reader)
            .map(graph: fixture.graph, environment: MapperEnvironment())
        verify(storage).fetch(
            .value(coverage ? [] : [CacheStorableItem(name: "Feature", hash: "feature")]),
            cacheCategory: .value(.binaries)
        ).called(1)
    }

    private func subject(
        fixture _: (graph: Graph, feature: GraphTarget),
        path: AbsolutePath,
        storage: MockCacheStoring,
        mutator: MockCacheGraphMutating,
        reader: MockCachedModuleDebuggingMetadataReading
    ) -> TargetsToCacheBinariesGraphMapper {
        TargetsToCacheBinariesGraphMapper(
            config: .test(),
            cacheGraphContentHasher: MockCacheGraphContentHashing(),
            decider: CacheProfileTargetReplacementDecider(profile: .allPossible, exceptions: []),
            configuration: "Debug",
            cacheGraphMutator: mutator,
            cacheStorage: storage,
            precomputedTargetHashes: [TargetReference(projectPath: path, name: "Feature"): .test(hash: "feature")],
            debuggingMetadataReader: reader
        )
    }

    private func fixture(at path: AbsolutePath, coverage: Bool) -> (graph: Graph, feature: GraphTarget) {
        let feature = Target.test(name: "Feature", product: .framework)
        let tests = Target.test(name: "Tests", product: .unitTests)
        let project = Project.test(path: path, targets: [feature, tests], schemes: [.test(
            testAction: .test(targets: [.init(target: .init(projectPath: path, name: "Tests"))], coverage: coverage)
        )])
        let graph = Graph.test(projects: [path: project], dependencies: [
            .target(name: "Tests", path: path): [.target(name: "Feature", path: path)],
        ])
        return (graph, GraphTarget(path: path, target: feature, project: project))
    }
}
