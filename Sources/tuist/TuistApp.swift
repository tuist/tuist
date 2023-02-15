import Foundation
import TSCBasic
import TuistAnalytics
import TuistKit
import TuistLoader
import TuistSupport

@main
enum TuistApp {
    static func main() async throws {
        if CommandLine.arguments.contains("--verbose") {
            try? ProcessEnv.setVar(Constants.EnvironmentVariables.verbose, value: "true")
        }

        TuistSupport.LogOutput.bootstrap()

        let path: AbsolutePath
        if let argumentIndex = CommandLine.arguments.firstIndex(of: "--path") {
            path = try AbsolutePath(validating: CommandLine.arguments[argumentIndex + 1], relativeTo: .current)
        } else {
            path = .current
        }

        try TuistSupport.Environment.shared.bootstrap()

        try TuistAnalytics.bootstrap(config: ConfigLoader().loadConfig(path: path))

        await TuistCommand.main()
    }
}
