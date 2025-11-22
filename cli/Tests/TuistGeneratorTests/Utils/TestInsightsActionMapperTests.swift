import FileSystem
import Foundation
import Mockable
import Testing
import TuistSupport
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
                    scriptText: "/mise/tuist inspect test",
                    target: target,
                    shellPath: nil
                ),
            ]
        )
        #expect(
            got == expectedTestAction
        )
    }
}
