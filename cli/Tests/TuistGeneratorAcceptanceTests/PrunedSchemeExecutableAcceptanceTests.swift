import Foundation
import Testing
import TuistGenerateCommand
import TuistTesting
import XcodeProj

struct PrunedSchemeExecutableAcceptanceTests {
    @Test(.withFixture("generated_scheme_with_pruned_executable"))
    func focused_generation_removes_pruned_executable_references() async throws {
        let fixtureDirectory = try #require(TuistTest.fixtureDirectory)

        try await TuistTest.run(
            GenerateCommand.self,
            [
                "tag:targets:units",
                "--path", fixtureDirectory.pathString,
                "--cache-profile", "none",
                "--no-open",
            ]
        )

        let projectPath = fixtureDirectory.appending(component: "Library.xcodeproj")
        let project = try XcodeProj(pathString: projectPath.pathString)
        #expect(project.pbxproj.nativeTargets.map(\.name).sorted() == ["Library", "LibraryUnitTests"])

        let scheme = try #require(project.sharedData?.schemes.first { $0.name == "Library" })
        #expect(scheme.testAction?.testables.map(\.buildableReference.blueprintName) == ["LibraryUnitTests"])

        let schemePath = projectPath.appending(components: "xcshareddata", "xcschemes", "Library.xcscheme")
        let schemeXML = try String(contentsOf: schemePath.url, encoding: .utf8)
        #expect(!schemeXML.contains("Demo"))
    }
}
