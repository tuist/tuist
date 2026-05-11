import FileSystem
import Foundation
import Mockable
import Testing
import TuistEnvironment
import TuistSupport
import TuistTesting
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

        // Then — the post-action's `target` is bound to the build action's first target so
        // Xcode's `<EnvironmentBuildable>` exposes build settings to the script. If focus later
        // prunes that target, `TreeShakePrunedTargetsGraphMapper` rewrites the reference to a
        // surviving buildable.
        var expectedBuildAction: BuildAction = .test(
            postActions: [
                ExecutionAction(
                    title: "Push build insights",
                    scriptText: "/mise/tuist inspect build",
                    target: buildAction.targets.first,
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
