import Testing
import TuistAcceptanceTesting
import TuistTesting

@testable import TuistInspectCommand
@testable import TuistKit

struct LintAcceptanceTests {
    @Test(.disabled(), .withFixture("generated_ios_app_with_headers"), .withMockedDependencies())
    func ios_app_with_headers() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        try await TuistTest.run(InspectImplicitImportsCommand.self, ["--path", fixtureDirectory.pathString])
        TuistTest.expectLogs(
            "We did not find any dependency issues in your project (checked: implicit).",
            at: .info,
            <=
        )
    }

    @Test(.disabled(), .withFixture("generated_ios_app_with_implicit_dependencies"), .withMockedDependencies())
    func ios_app_with_implicit_dependencies() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let appDependencies: Set<String> = [
            "ClassModule",
            "EnumModule",
            "FuncModule",
            "LetModule",
            "ProtocolModule",
            "StructModule",
            "TypeAliasModule",
            "VarModule",
        ]
        await #expect(throws: InspectImportsServiceError.issuesFound(implicit: [
            .init(target: "App", dependencies: appDependencies),
            .init(target: "FrameworkA", dependencies: ["FrameworkB"]),
        ])) {
            try await TuistTest.run(InspectImplicitImportsCommand.self, ["--path", fixtureDirectory.pathString])
        }
    }

    @Test(.disabled(), .withFixture("generated_framework_with_macros_and_tests"), .withMockedDependencies())
    func framework_with_macros_redundant_imports() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        try await TuistTest.run(InstallCommand.self, ["--path", fixtureDirectory.pathString])
        try await TuistTest.run(InspectRedundantImportsCommand.self, ["--path", fixtureDirectory.pathString])
        TuistTest.expectLogs(
            "We did not find any dependency issues in your project (checked: redundant).",
            at: .info,
            <=
        )
    }
}
