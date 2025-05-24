import TuistAcceptanceTesting
import TuistSupport
import TuistSupportTesting
import XcodeProj
import XCTest

final class ListTargetsAcceptanceTestiOSWorkspaceWithMicrofeatureArchitecture: TuistAcceptanceTestCase {
    func test_ios_workspace_with_microfeature_architecture() async throws {
        try await withMockedDependencies {
            try await setUpFixture(.iosWorkspaceWithMicrofeatureArchitecture)
            try await run(GenerateCommand.self)
            try await listTargets(for: "UIComponents")
            try await listTargets(for: "Core")
            try await listTargets(for: "Data")
        }
    }
}

extension TuistAcceptanceTestCase {
    fileprivate func listTargets(
        for framework: String
    ) async throws {
        let frameworkXcodeprojPath = fixturePath.appending(
            components: [
                "Frameworks",
                "\(framework)Framework",
                "\(framework).xcodeproj",
            ]
        )

        try await run(MigrationTargetsByDependenciesCommand.self, "-p", frameworkXcodeprojPath.pathString)
        XCTAssertStandardOutput(
            pattern:
            """
            "targetName" : "\(framework)"
            """
        )
    }
}
