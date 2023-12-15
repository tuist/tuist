import TSCBasic
import TuistAcceptanceTesting
import TuistSupport
import TuistSupportTesting
import XcodeProj
import XCTest

final class BuildRulesAcceptanceTestAppWithBuildRules: TuistAcceptanceTestCase {
    func test_app_with_build_rules() async throws {
        try run(InitCommand.self, "--platform", "macos", "--name", "Test")
        try await run(BuildCommand.self)
    }
}

//Feature: Build projects using Tuist build
//  Scenario: The project is an application with build rules (app_with_build_rules)
//    Given that tuist is available
//    And I have a working directory
//    Then I copy the fixture app_with_build_rules into the working directory
//    Then tuist generates the project
//    Then I should be able to build for iOS the scheme App
//    Then the target App should have the build rule Process_InfoPlist.strings with pattern */InfoPlist.strings
