import FileSystemTesting
import Testing
import TuistAcceptanceTesting
import TuistSupport
import TuistTesting
import XcodeProj

@testable import TuistKit

struct BuildRulesAcceptanceTests {
    @Test(.withFixture("generated_app_with_build_rules"), .inTemporaryDirectory)
    func app_with_build_rules() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)

        try await TuistTest.run(GenerateCommand.self, ["--path", fixtureDirectory.pathString, "--no-open"])
        try await TuistTest.run(
            BuildCommand.self,
            ["--path", fixtureDirectory.pathString, "--derived-data-path", temporaryDirectory.pathString]
        )

        let xcodeprojPath = try TuistAcceptanceTest.xcodeprojPath(in: fixtureDirectory)
        let xcodeproj = try XcodeProj(pathString: xcodeprojPath.pathString)
        let target = try #require(xcodeproj.pbxproj.projects.flatMap(\.targets).first(where: { $0.name == "App" }))
        let buildRule = try #require(target.buildRules.first(where: { $0.name == "Process_InfoPlist.strings" }))
        #expect(buildRule.filePatterns == "*/InfoPlist.strings")
    }
}
