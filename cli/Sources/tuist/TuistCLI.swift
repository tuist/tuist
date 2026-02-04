import Foundation
import Path

@main
@_documentation(visibility: private)
private enum TuistCLI {
    static func main() async throws {
        try await initDependencies { sessionPaths in
            try await TuistCommand.main(sessionPaths: sessionPaths)
        }
    }
}
