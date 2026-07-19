import Command
import Mockable
import Testing
import TuistEnvironment
@testable import TuistSupport

struct SwiftVersionProviderTests {
    private let commandRunner = MockCommandRunning()
    private let subject: SwiftVersionProvider

    init() {
        subject = SwiftVersionProvider(commandRunner: commandRunner)
    }

    @Test func swift_default_language_mode_version_returns_canonical_version_and_caches_it() async throws {
        given(commandRunner)
            .run(
                arguments: .value([
                    "/usr/bin/xcrun",
                    "swift",
                    "-e",
                    SwiftVersionProvider.swiftDefaultLanguageModeVersionProbe,
                ]),
                environment: .value(Environment.current.manifestLoadingVariables),
                workingDirectory: .any
            )
            .willReturn(outputStream("5\n"))

        let first = try await subject.swiftDefaultLanguageModeVersion()
        let second = try await subject.swiftDefaultLanguageModeVersion()

        #expect(first == "5")
        #expect(second == "5")
        verify(commandRunner)
            .run(
                arguments: .any,
                environment: .any,
                workingDirectory: .any
            )
            .called(1)
    }

    @Test func swift_default_language_mode_version_throws_on_unexpected_output() async throws {
        given(commandRunner)
            .run(
                arguments: .any,
                environment: .any,
                workingDirectory: .any
            )
            .willReturn(outputStream("5.10\n"))

        await #expect(throws: SwiftVersionProviderError.parseSwiftDefaultLanguageModeVersion("5.10\n")) {
            try await subject.swiftDefaultLanguageModeVersion()
        }
    }

    private func outputStream(_ output: String) -> AsyncThrowingStream<CommandEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.standardOutput(Array(output.utf8)))
            continuation.finish()
        }
    }
}
