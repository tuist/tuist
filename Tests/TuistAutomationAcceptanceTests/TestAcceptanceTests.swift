import Path
import TuistAcceptanceTesting
import TuistSupport
import TuistSupportTesting
import XCTest

@testable import TuistKit

/// Test projects using tuist test
final class TestAcceptanceTests: TuistAcceptanceTestCase {
    func test_with_app_with_framework_and_tests() async throws {
        try await setUpFixture(.appWithFrameworkAndTests)
        try await run(TestCommand.self)
        try await run(TestCommand.self, "App")
        try await run(TestCommand.self, "--test-targets", "FrameworkTests/FrameworkTests")
        try await run(TestCommand.self, "App", "--", "-testLanguage", "en")
    }

    func test_with_app_with_test_plan() async throws {
        try await setUpFixture(.appWithTestPlan)
        try await run(TestCommand.self)
        try await run(TestCommand.self, "App", "--test-plan", "All")
    }

    func test_with_invalid_arguments() async throws {
        try await setUpFixture(.appWithFrameworkAndTests)
        await XCTAssertThrowsSpecific(
            try await run(TestCommand.self, "App", "--", "-scheme", "App"),
            XcodeBuildPassthroughArgumentError.alreadyHandled("-scheme")
        )
        await XCTAssertThrowsSpecific(
            try await run(TestCommand.self, "App", "--", "-project", "App"),
            XcodeBuildPassthroughArgumentError.alreadyHandled("-project")
        )
        await XCTAssertThrowsSpecific(
            try await run(TestCommand.self, "App", "--", "-workspace", "App"),
            XcodeBuildPassthroughArgumentError.alreadyHandled("-workspace")
        )
        await XCTAssertThrowsSpecific(
            try await run(TestCommand.self, "App", "--", "-testPlan", "TestPlan"),
            XcodeBuildPassthroughArgumentError.alreadyHandled("-testPlan")
        )
        await XCTAssertThrowsSpecific(
            try await run(TestCommand.self, "App", "--", "-skip-test-configuration", "TestPlan"),
            XcodeBuildPassthroughArgumentError.alreadyHandled("-skip-test-configuration")
        )
        await XCTAssertThrowsSpecific(
            try await run(TestCommand.self, "App", "--", "-only-test-configuration", "TestPlan"),
            XcodeBuildPassthroughArgumentError.alreadyHandled("-only-test-configuration")
        )
        await XCTAssertThrowsSpecific(
            try await run(TestCommand.self, "App", "--", "-only-testing", "AppTests"),
            XcodeBuildPassthroughArgumentError.alreadyHandled("-only-testing")
        )
        await XCTAssertThrowsSpecific(
            try await run(TestCommand.self, "App", "--", "-skip-testing", "AppTests"),
            XcodeBuildPassthroughArgumentError.alreadyHandled("-skip-testing")
        )
        // SystemError is verbose and would lead to flakyness
        // xcodebuild: error: The flag -addressSanitizerEnabled must be supplied with an argument YES or NO
        await XCTAssertThrows(
            try await run(TestCommand.self, "App", "--", "-parallelizeTargets", "YES", "-enableAddressSanitizer")
        )
        // xcodebuild: error: option '-configuration' may only be provided once
        // Usage: xcodebuild [-project <projectname>] ...
        await XCTAssertThrows(
            try await run(TestCommand.self, "App", "--configuration", "Debug", "--", "-configuration", "Debug")
        )
    }
}

// Feature: Tests projects using Tuist test
//  # TODO: Fix
//  # Scenario: The project is an application with tests (app_with_tests)
//  #   Given that tuist is available
//  #   And I have a working directory
//  #   Then I copy the fixture app_with_tests into the working directory
//  #   Then tuist generates the project
//  #   Then tuist tests the project
//  #   Then tuist tests the scheme App-Workspace-iOS from the project
//  #   Then tuist tests the scheme App-Workspace-macOS from the project
//  #   Then tuist tests the scheme App-Workspace-tvOS from the project
//  #   Then tuist tests the scheme App from the project
//  #   Then tuist tests the scheme MacFramework from the project
//  #   Then tuist tests the scheme App and configuration Debug from the project
//
//  # TODO: Fix
//  # Scenario: The project is an application with tests (app_with_tests)
//  #   Given that tuist is available
//  #   And I have a working directory
//  #   Then I copy the fixture app_with_tests into the working directory
//  #   Then tuist tests the project
//  #   Then App-Workspace-iOS scheme has something to test
//  #   Then generated project is deleted
//  #   Then tuist tests the project
//  #   Then App-Workspace-iOS scheme has nothing to test
//  #   Then generated project is deleted
//  #   Then I add an empty line at the end of the file Targets/App/Sources/AppDelegate.swift
//  #   Then tuist tests the project
//  #   Then App-Workspace-iOS scheme has something to test

// Then(/^generated project is deleted/) do
//   FileUtils.rm_rf(@workspace_path)
//   FileUtils.rm_rf(@xcodeproj_path)
// end

// Then(/^([a-zA-Z-]+) scheme has nothing to test/) do |scheme_name|
//   scheme_file = File.join(Xcodeproj::Workspace.new_from_xcworkspace(@workspace_path).schemes[scheme_name],
//                           'xcshareddata', 'xcschemes', "#{scheme_name}.xcscheme")
//   scheme = Xcodeproj::XCScheme.new(scheme_file)
//   flunk("Project #{scheme_name} scheme has nothing to test") unless scheme.test_action.testables.empty?
// end

// Then(/^([a-zA-Z-]+) scheme has something to test/) do |scheme_name|
//   scheme_file = File.join(Xcodeproj::Workspace.new_from_xcworkspace(@workspace_path).schemes[scheme_name],
//                           'xcshareddata', 'xcschemes', "#{scheme_name}.xcscheme")
//   scheme = Xcodeproj::XCScheme.new(scheme_file)
//   flunk("Project #{scheme_name} scheme has nothing to test") if scheme.test_action.testables.empty?
// end
