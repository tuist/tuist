import FileSystem
import Foundation
import Mockable
import Testing
import TuistEnvironment
import TuistSupport
import TuistTesting
import XcodeGraph

@testable import TuistGenerator

struct TestInsightsActionMapperTests {
    private let subject: TestInsightsActionMapper

    init() {
        subject = TestInsightsActionMapper()
    }

    @Test func map_when_disabled() async throws {
        // Given
        let testAction: TestAction = .test()

        // When
        let got = try await subject.map(
            testAction,
            target: nil,
            testInsightsDisabled: true
        )

        // Then
        #expect(got == testAction)
    }

    @Test func map_when_nil() async throws {
        // When
        let got = try await subject.map(
            nil,
            target: nil,
            testInsightsDisabled: false
        )

        // Then
        #expect(got == nil)
    }

    @Test(.withMockedEnvironment()) func map() async throws {
        // Given
        let testAction: TestAction = .test()
        let target = TargetReference(projectPath: "/tmp/project", name: "AppTests")
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.currentExecutablePathStub = "/mise/tuist"

        // When
        let got = try await subject.map(
            testAction,
            target: target,
            testInsightsDisabled: false
        )

        // Then
        let expectedTestAction: TestAction = .test(
            postActions: [
                ExecutionAction(
                    title: "Push test insights",
                    scriptText: "/mise/tuist inspect test || echo \"warning: tuist inspect test failed, test insights were not uploaded\"",
                    target: target,
                    shellPath: nil
                ),
            ]
        )
        #expect(
            got == expectedTestAction
        )
    }

    @Test(.withMockedEnvironment()) func map_generates_a_script_that_cannot_fail_the_test_action() async throws {
        // Given
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.currentExecutablePathStub = "/nonexistent/tuist"

        let testAction: TestAction = .test()

        // When
        let got = try await subject.map(
            testAction,
            target: nil,
            testInsightsDisabled: false
        )

        // Then
        let scriptText = try #require(got?.postActions.first?.scriptText)
        let result = try runThroughShell(scriptText)
        #expect(result.exitCode == 0)
        #expect(result.standardOutput.contains("warning: tuist inspect test failed"))
    }
}
