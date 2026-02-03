import Foundation
import Path

@main
@_documentation(visibility: private)
private enum TuistCLI {
    static func main() async throws {
        try await initDependencies { logFilePath in
            try await TuistCommand.main(logFilePath: logFilePath)
        }
    }
}
