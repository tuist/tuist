import TSCBasic
import TuistAcceptanceTesting
import TuistSupport
import TuistSupportTesting
import XcodeProj
import XCTest

final class BuildRulesAcceptanceTestAppWithBuildRules: TuistAcceptanceTestCase {
    func test_app_with_build_rules() async throws {
        let context = MockContext()
        try setUpFixture(.appWithBuildRules)
        try await run(GenerateCommand.self, context: context)
        try await run(BuildCommand.self, context: context)
        let xcodeproj = try XcodeProj(pathString: xcodeprojPath.pathString)
        let target = try XCTUnwrapTarget("App", in: xcodeproj)
        let buildRule = try XCTUnwrap(target.buildRules.first(where: { $0.name == "Process_InfoPlist.strings" }))
        XCTAssertEqual(buildRule.filePatterns, "*/InfoPlist.strings")
    }
}
