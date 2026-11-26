import Path
import Testing
import TuistCore
import XcodeGraph
@testable import TuistInspectCommand
@testable import TuistKit

struct GraphImportsLinterTests {
    @Test(arguments: [
        (true, InspectType.redundant, [InspectImportsIssue]()),
        (false, .implicit, [InspectImportsIssue(target: "App", dependencies: ["DesignSystem"])]),
    ])
    func lint_keepsImportsGuardedBySystemModules(
        declaresDesignSystem: Bool,
        inspectType: InspectType,
        expectedIssues: [InspectImportsIssue]
    ) async throws {
        let issues = try await lint(
            sourceCode: """
            #if canImport(UIKit) || canImport(AppKit)
            import DesignSystem
            #endif
            """,
            appDependencies: declaresDesignSystem ? ["DesignSystem"] : [],
            inspectType: inspectType
        )

        #expect(issues == expectedIssues)
    }

    @Test func lint_skipsImportsGuardedByUnreachableGraphModules() async throws {
        let issues = try await lint(
            sourceCode: """
            #if canImport(Analytics) && canImport(FeatureKit)
            import Analytics
            #endif
            """,
            appDependencies: ["FeatureKit"],
            inspectType: .implicit
        )

        #expect(issues == [])
    }

    private func lint(
        sourceCode: String,
        appDependencies: [String],
        inspectType: InspectType
    ) async throws -> [InspectImportsIssue] {
        let path = try AbsolutePath(validating: "/project")
        let app = Target.test(
            name: "App",
            product: .app,
            sources: [SourceFile(path: path.appending(components: "App", "App.swift"))]
        )
        let frameworks = ["Analytics", "DesignSystem", "FeatureKit"].map { Target.test(name: $0, product: .framework) }
        let graph = Graph.test(
            path: path,
            projects: [path: Project.test(path: path, targets: [app] + frameworks)],
            dependencies: [
                .target(name: app.name, path: path): Set(appDependencies.map { .target(name: $0, path: path) }),
            ]
        )
        let targetScanner = TargetImportsScanner { $0.basename == "App.swift" ? sourceCode : nil }

        return try await GraphImportsLinter(targetScanner: targetScanner)
            .lint(graphTraverser: GraphTraverser(graph: graph), inspectType: inspectType, ignoreTagsMatching: [])
    }
}
