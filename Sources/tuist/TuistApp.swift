import Foundation
import Path
import TSCBasic
import TuistKit
import TuistLoader
import TuistSupport

@main
@_documentation(visibility: private)
private enum TuistServer {
    static func main() async throws {
        if CommandLine.arguments.contains("--verbose") {
            try? ProcessEnv.setVar(Constants.EnvironmentVariables.verbose, value: "true")
        }

        TuistSupport.LogOutput.bootstrap()

        try TuistSupport.Environment.shared.bootstrap()

        try await TuistCommand.main()
    }
}
