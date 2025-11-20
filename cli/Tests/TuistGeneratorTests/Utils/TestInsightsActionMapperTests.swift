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
            testInsightsDisabled: true
        )

        // Then
        #expect(got == testAction)
    }

    @Test func map_when_nil() async throws {
        // When
        let got = try await subject.map(
            nil,
            testInsightsDisabled: false
        )

        // Then
        #expect(got == nil)
    }

    @Test(.withMockedEnvironment()) func map() async throws {
        // Given
        let testAction: TestAction = .test()
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.currentExecutablePathStub = "/mise/tuist"

        // When
        let got = try await subject.map(
            testAction,
            testInsightsDisabled: false
        )

        // Then
        var expectedTestAction: TestAction = .test(
            postActions: [
                ExecutionAction(
                    title: "Push test insights",
                    scriptText: "/mise/tuist inspect test",
                    target: nil,
                    shellPath: nil
                ),
            ]
        )
        #expect(
            got == expectedTestAction
        )
    }
}
