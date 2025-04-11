import Foundation
import Path
import ServiceContextModule
import Testing
import TuistSupport
@testable import TuistKit

struct MCPServerCommandResolverTests {
    @Test func resolve_whenMiseIsNotUsed() async throws {
        try await ServiceContext.withTestingDependencies {
            // Given
            let executablePath = "/usr/local/bin/tuist"
            let subject = MCPServerCommandResolver()
            ServiceContext.current!.testEnvironment?.currentExecutablePathStub = try AbsolutePath(validating: executablePath)

            // When
            let (command, args) = subject.resolve()

            // Then
            #expect(command == executablePath)
            #expect(args == ["mcp", "start"])
        }
    }
}
