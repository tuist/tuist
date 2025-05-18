import FileSystem
import Foundation
import Mockable
import Path
import ServiceContextModule
import Testing
import TuistSupportTesting
@testable import TuistKit

struct MCPSetupClaudeCommandServiceTests {
    private let fileSystem = FileSystem()
    private let configurationFileController = MockMCPConfigurationFileControlling()
    private let subject: MCPSetupClaudeCommandService

    init() {
        subject = MCPSetupClaudeCommandService(
            fileSystem: fileSystem,
            configurationFileController: configurationFileController
        )
    }

    @Test func run() async throws {
        try await ServiceContext.withTestingDependencies {
            // Given
            given(configurationFileController)
                .update(at: .value(try AbsolutePath(validating: NSHomeDirectory()).appending(components: [
                    "Library",
                    "Application Support",
                    "Claude",
                    "claude_desktop_config.json",
                ]))).willReturn()

            // When
            try await subject.run()

            // Then
            #expect(ui() == """
            ✔ Success
              Claude configured to point to the Tuist's MCP server.

              Takeaways:
               ▸ Restart the Claude app if it was opened
               ▸ Check out Claude's <documentation: https://modelcontextprotocol.io/quickstart/user>
            """)
        }
    }
}
