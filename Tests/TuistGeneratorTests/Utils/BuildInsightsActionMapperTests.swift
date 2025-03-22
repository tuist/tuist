import FileSystem
import Foundation
import Mockable
import Testing
import TuistCore
import XcodeGraph

@testable import TuistGenerator

struct BuildInsightsActionMapperTests {
    private let rootDirectoryLocator = MockRootDirectoryLocating()
    private let fileSystem = FileSystem()
    private let subject: BuildInsightsActionMapper

    init() {
        subject = BuildInsightsActionMapper(
            rootDirectoryLocator: rootDirectoryLocator,
            fileSystem: fileSystem
        )
    }

    @Test func map_when_disabled() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given
            let buildAction: BuildAction = .test()

            // When
            let got = try await subject.map(
                buildAction,
                buildInsightsDisabled: true,
                path: temporaryDirectory
            )

            // Then
            #expect(got == buildAction)
        }
    }

    @Test func map_when_without_mise() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given
            let buildAction: BuildAction = .test()
            given(rootDirectoryLocator)
                .locate(from: .any)
                .willReturn(temporaryDirectory)

            // When
            let got = try await subject.map(
                buildAction,
                buildInsightsDisabled: false,
                path: temporaryDirectory
            )

            // Then
            var expectedBuildAction: BuildAction = .test(
                postActions: [
                    ExecutionAction(
                        title: "Build insights",
                        scriptText: "tuist inspect build",
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

    @Test func map_when_with_mise() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given
            let buildAction: BuildAction = .test()
            given(rootDirectoryLocator)
                .locate(from: .any)
                .willReturn(temporaryDirectory)
            try await fileSystem.touch(temporaryDirectory.appending(component: "mise.toml"))

            // When
            let got = try await subject.map(
                buildAction,
                buildInsightsDisabled: false,
                path: temporaryDirectory
            )

            // Then
            var expectedBuildAction: BuildAction = .test(
                postActions: [
                    ExecutionAction(
                        title: "Build insights",
                        scriptText: """
                        eval "$($HOME/.local/bin/mise activate -C $SRCROOT bash --shims)"

                        tuist inspect build
                        """,
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
}
