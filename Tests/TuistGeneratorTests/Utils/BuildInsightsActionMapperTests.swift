import FileSystem
import Foundation
import Mockable
import Testing
import TuistSupport
import XcodeGraph

@testable import TuistGenerator

struct BuildInsightsActionMapperTests {
    private let subject: BuildInsightsActionMapper

    init() {
        subject = BuildInsightsActionMapper()
    }

    @Test func map_when_disabled() async throws {
        // Given
        let buildAction: BuildAction = .test()

        // When
        let got = try await subject.map(
            buildAction,
            buildInsightsDisabled: true
        )

        // Then
        #expect(got == buildAction)
    }

    @Test(.withMockedEnvironment()) func map() async throws {
        // Given
        let buildAction: BuildAction = .test()
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.currentExecutablePathStub = "/mise/tuist"

        // When
        let got = try await subject.map(
            buildAction,
            buildInsightsDisabled: false
        )

        // Then
        var expectedBuildAction: BuildAction = .test(
            postActions: [
                ExecutionAction(
                    title: "Push build insights",
                    scriptText: "/mise/tuist inspect build",
                    target: nil,
                    shellPath: nil
                ),
            ]
        )
        expectedBuildAction.runPostActionsOnFailure = true
        #expect(
            got == expectedBuildAction
        )
    }
}
