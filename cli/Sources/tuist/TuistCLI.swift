import Foundation
import Path
import TuistCLICore

@main
@_documentation(visibility: private)
private enum TuistCLI {
    static func main() async throws {
        try await initDependencies { sessionPaths in
            try await TuistCommand.main(
                logFilePath: sessionPaths.logFilePath,
                sessionDirectory: sessionPaths.sessionDirectory,
                networkFilePath: sessionPaths.networkFilePath
            )
        }
    }
}
