import TSCBasic
import TuistAcceptanceTesting
import TuistSupport
import TuistSupportTesting
import XcodeProj
import XCTest

final class ListTargetsAcceptanceTestiOSWorkspaceWithMicrofeatureArchitecture: TuistAcceptanceTestCase {
    func test_ios_workspace_with_microfeature_architecture() async throws {
        let context = MockContext()
        try setUpFixture(.iosWorkspaceWithMicrofeatureArchitecture)
        try await run(GenerateCommand.self, context: context)
        try listTargets(for: "UIComponents", context: context)
        try listTargets(for: "Core", context: context)
        try listTargets(for: "Data", context: context)
    }
}

extension TuistAcceptanceTestCase {
    fileprivate func listTargets(
        for framework: String,
        context: Context
    ) throws {
        let frameworkXcodeprojPath = fixturePath.appending(
            components: [
                "Frameworks",
                "\(framework)Framework",
                "\(framework).xcodeproj",
            ]
        )

        try run(MigrationTargetsByDependenciesCommand.self, "-p", frameworkXcodeprojPath.pathString, context: context)
        XCTAssertStandardOutput(
            pattern:
            """
            "targetName" : "\(framework)"
            """
        )
    }
}
