import Foundation
import Path
import Testing
import TuistCore
import TuistTesting
import XcodeGraph

@testable import TuistKit

struct InstrumentedBinaryCacheWarmGraphMapperTests {
    @Test func map_marksRepositoryProjectsOnly() async throws {
        let localPath = try AbsolutePath(validating: "/local")
        let externalPath = try AbsolutePath(validating: "/external")
        let local = Project.test(path: localPath, settings: .test(base: ["SWIFT_VERSION": "5"]), type: .local)
        let external = Project.test(path: externalPath, type: .external(hash: nil))
        let graph = Graph.test(projects: [localPath: local, externalPath: external])

        let (got, sideEffects, _) = try await InstrumentedBinaryCacheWarmGraphMapper().map(
            graph: graph,
            environment: MapperEnvironment()
        )

        #expect(sideEffects.isEmpty)
        #expect(got.projects[localPath]?.settings.base == ["SWIFT_VERSION": "5", "TUIST_BINARY_CACHE_COVERAGE": "YES"])
        #expect(got.projects[externalPath]?.settings.base["TUIST_BINARY_CACHE_COVERAGE"] == nil)
    }
}
