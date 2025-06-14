import Foundation
import Testing
@testable import TuistKit

struct MCPServerCommandResolverTests {
    @Test func resolve_whenMiseIsNotUsed() {
        // Given
        let executablePath = "/usr/local/bin/tuist"
        let subject = MCPServerCommandResolver(executablePath: executablePath)

        // When
        let (command, args) = subject.resolve()

        // Then
        #expect(command == executablePath)
        #expect(args == ["mcp", "start"])
    }
}
