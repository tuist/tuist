import Testing
import TuistSupport
import TuistTesting

@testable import TuistKit

struct ListTargetsAcceptanceTests {
    @Test(.withFixture("generated_ios_workspace_with_microfeature_architecture"), .withMockedDependencies)
    func ios_workspace_with_microfeature_architecture() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        try await TuistTest.run(GenerateCommand.self, ["--path", fixtureDirectory.pathString, "--no-open"])
        try await listTargets(in: fixtureDirectory, framework: "UIComponents")
        try await listTargets(in: fixtureDirectory, framework: "Core")
        try await listTargets(in: fixtureDirectory, framework: "Data")
    }
}

private func listTargets(in fixtureDirectory: AbsolutePath, framework: String) async throws {
    let frameworkXcodeprojPath = fixtureDirectory.appending(
        components: [
            "Frameworks",
            "\(framework)Framework",
            "\(framework).xcodeproj",
        ]
    )

    try await TuistTest.run(
        MigrationTargetsByDependenciesCommand.self,
        ["-p", frameworkXcodeprojPath.pathString]
    )
    TuistTest.expectLogs(
        """
        "targetName" : "\(framework)"
        """,
        at: .info,
        <=
    )
}
