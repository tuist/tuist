import Foundation
import Testing
@testable import TuistKit

struct MCPServerCommandResolverTests {
    @Test func resolve_whenMiseIsUsed() {
        // Given
        let executablePath = "/Users/test/.local/share/mise/installs/tuist/4.45.0/bin/tuist"
        let subject = MCPServerCommandResolver(executablePath: executablePath)

        // When
        let (command, args) = subject.resolve()

        // Then
        #expect(command == "mise")
        #expect(args == ["x", "tuist@latest", "--", "tuist", "mcp"])
    }

    @Test func resolve_whenMiseIsNotUsed() {
        // Given
        let executablePath = "/usr/local/bin/tuist"
        let subject = MCPServerCommandResolver(executablePath: executablePath)

        // When
        let (command, args) = subject.resolve()

        // Then
        #expect(command == executablePath)
        #expect(args == ["mcp"])
    }
}
