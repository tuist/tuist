import TSCBasic
import TuistAcceptanceTesting
import TuistSupport
import TuistSupportTesting
import XcodeProj
import XCTest

final class ListTargetsAcceptanceTestiOSWorkspaceWithMicrofeatureArchitecture: TuistAcceptanceTestCase {
    func test_ios_workspace_with_microfeature_architecture() async throws {
        try setUpFixture(.iosWorkspaceWithMicrofeatureArchitecture)
        try await run(GenerateCommand.self)
        try listTargets(for: "UIComponents")
        try listTargets(for: "Core")
        try listTargets(for: "Data")
    }
}

extension TuistAcceptanceTestCase {
    fileprivate func listTargets(
        for framework: String
    ) throws {
        let frameworkXcodeprojPath = fixturePath.appending(
            components: [
                "Frameworks",
                "\(framework)Framework",
                "\(framework).xcodeproj",
            ]
        )

        try run(MigrationTargetsByDependenciesCommand.self, "-p", frameworkXcodeprojPath.pathString)
        XCTAssertStandardOutput(
            pattern:
            """
            "targetName" : "\(framework)"
            """
        )
    }
}
