import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistCore
import XcodeGraph
@testable import TuistCache

struct CachedModuleCoverageSourcePolicyTests {
    @Test(arguments: [false, true])
    func retainsTransitiveAndExternalSourcesOnlyWhenCoverageIsRequested(coverage: Bool) async throws {
        let result = try await CachedModuleCoverageSourcePolicy().sourceTargets(in: graph(coverage: coverage))
        #expect(Set(result.map(\.name)) == (coverage ? ["Tests", "Feature", "External"] : []))
    }

    @Test
    func automationUsesTheSelectedSchemeRatherThanAnUnrelatedCoverageScheme() async throws {
        let result = try await CachedModuleCoverageSourcePolicy().sourceTargets(in: graph(coverage: true), schemeName: "Other")
        #expect(result.isEmpty)
    }

    @Test(.inTemporaryDirectory, arguments: [false, true])
    func readsReferencedPlanCoverageInsteadOfDisablingAllPlanBasedCacheHits(coverage: Bool) async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let path = root.appending(component: "Tests.xctestplan")
        try await FileSystem().writeText("{\"version\":1,\"defaultOptions\":{\"codeCoverage\":\(coverage)}}", at: path)
        let plan = TestPlan(path: path, testTargets: [], isDefault: true)
        let result = try await CachedModuleCoverageSourcePolicy().sourceTargets(in: graph(coverage: false, plan: plan))
        #expect(Set(result.map(\.name)) == (coverage ? ["Tests", "Feature", "External"] : []))
    }

    @Test(.inTemporaryDirectory)
    func honorsCoverageOverridesInEveryPlanConfiguration() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let path = root.appending(component: "Tests.xctestplan")
        let plan = TestPlan(path: path, testTargets: [], isDefault: true)
        try await FileSystem().writeText(
            #"{"version":1,"defaultOptions":{"codeCoverage":true},"configurations":[{"options":{"codeCoverage":false}}]}"#,
            at: path
        )
        #expect(try await CachedModuleCoverageSourcePolicy().sourceTargets(in: graph(coverage: true, plan: plan)).isEmpty)
        try await FileSystem().writeText(
            #"{"version":1,"defaultOptions":{"codeCoverage":false},"configurations":[{"options":{}},{"options":{"codeCoverage":true}}]}"#,
            at: path
        )
        #expect(try await CachedModuleCoverageSourcePolicy().sourceTargets(in: graph(coverage: false, plan: plan)).count == 3)
    }

    @Test(.inTemporaryDirectory)
    func missingOrUnsupportedPlansCannotSilentlyReuseOrdinaryArtifacts() async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let path = root.appending(component: "Tests.xctestplan")
        let plan = TestPlan(path: path, testTargets: [], isDefault: true)
        #expect(try await CachedModuleCoverageSourcePolicy().sourceTargets(in: graph(coverage: false, plan: plan)).count == 3)
        try await FileSystem().writeText(#"{"version":99,"defaultOptions":{"codeCoverage":false}}"#, at: path)
        #expect(try await CachedModuleCoverageSourcePolicy().sourceTargets(in: graph(coverage: false, plan: plan)).count == 3)
    }

    private func graph(coverage: Bool, plan: TestPlan? = nil) throws -> Graph {
        let path = try AbsolutePath(validating: "/Workspace")
        let external = try AbsolutePath(validating: "/Packages")
        let test = TargetReference(projectPath: path, name: "Tests")
        return Graph.test(
            workspace: .test(schemes: [.test(
                name: "Coverage",
                testAction: .test(
                    targets: [TestableTarget(target: test)],
                    coverage: coverage,
                    testPlans: plan.map { [$0] }
                )
            )]),
            dependencies: [
                .target(name: "Tests", path: path): [.target(name: "Feature", path: path)],
                .target(name: "Feature", path: path): [.target(name: "External", path: external)],
            ]
        )
    }
}
