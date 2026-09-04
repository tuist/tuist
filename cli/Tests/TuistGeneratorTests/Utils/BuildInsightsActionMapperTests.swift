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
            target: nil,
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
            target: nil,
            buildInsightsDisabled: false
        )

        // Then
        var expectedBuildAction: BuildAction = .test(
            postActions: [
                ExecutionAction(
                    title: "Push build insights",
                    scriptText: "/mise/tuist inspect build || echo \"warning: tuist inspect build failed, build insights were not uploaded\"",
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

    @Test(.withMockedEnvironment()) func map_with_target() async throws {
        // Given
        let buildAction: BuildAction = .test()
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.currentExecutablePathStub = "/mise/tuist"

        // When
        let got = try await subject.map(
            buildAction,
            target: TargetReference(projectPath: "/tmp/project", name: "TargetA"),
            buildInsightsDisabled: false
        )

        // Then
        var expectedBuildAction: BuildAction = .test(
            postActions: [
                ExecutionAction(
                    title: "Push build insights",
                    scriptText: "/mise/tuist inspect build || echo \"warning: tuist inspect build failed, build insights were not uploaded\"",
                    target: TargetReference(projectPath: "/tmp/project", name: "TargetA"),
                    shellPath: nil
                ),
            ]
        )
        expectedBuildAction.runPostActionsOnFailure = true
        #expect(
            got == expectedBuildAction
        )
    }

    @Test(.withMockedEnvironment()) func map_generates_a_script_that_cannot_fail_the_build() async throws {
        // Given
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.currentExecutablePathStub = "/nonexistent/tuist"

        let buildAction: BuildAction = .test()

        // When
        let got = try await subject.map(
            buildAction,
            target: nil,
            buildInsightsDisabled: false
        )

        // Then
        let scriptText = try #require(got.postActions.first?.scriptText)
        let result = try runThroughShell(scriptText)
        #expect(result.exitCode == 0)
        #expect(result.standardOutput.contains("warning: tuist inspect build failed"))
    }
}

func runThroughShell(_ scriptText: String) throws -> (exitCode: Int32, standardOutput: String) {
    // Xcode runs an execution action with no explicit shellPath through /bin/sh.
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", scriptText]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
}
