import FileSystem
import Foundation
import Mockable
import Path
import ServiceContextModule
import Testing
import TuistSupportTesting
@testable import TuistKit

struct MCPSetupCursorCommandServiceTests {
    private let fileSystem = FileSystem()
    private let configurationFileController = MockMCPConfigurationFileControlling()
    private let subject: MCPSetupCursorCommandService

    init() {
        subject = MCPSetupCursorCommandService(
            fileSystem: fileSystem,
            configurationFileController: configurationFileController
        )
    }

    @Test func run() async throws {
        try await ServiceContext.withTestingDependencies {
            // Given
            let directory: AbsolutePath = try AbsolutePath(validating: "/path/to/project")
            let mcpConfigPath = directory.appending(components: [".cursor", "mcp.json"])

            given(configurationFileController).update(at: .value(mcpConfigPath)).willReturn()

            // When
            try await subject.run(directory: directory)

            // Then
            #expect(ServiceContext.current?.recordedUI() == """
            ▌ ✔ Success
            ▌ Cursor configuration at ../path/to/project/.cursor/mcp.json connected to the Tuist MCP server.
            """)
        }
    }
}
