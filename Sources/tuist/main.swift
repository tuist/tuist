import Foundation
import TSCBasic
import TuistAnalytics
import TuistLoader
import TuistSupport

if CommandLine.arguments.contains("--verbose") { try? ProcessEnv.setVar(Constants.EnvironmentVariables.verbose, value: "true") }

TuistSupport.LogOutput.bootstrap()

let path: AbsolutePath
if let argumentIndex = CommandLine.arguments.firstIndex(of: "--path") {
    path = AbsolutePath(CommandLine.arguments[argumentIndex + 1], relativeTo: .current)
} else {
    path = .current
}

try TuistAnalytics.bootstrap(config: ConfigLoader().loadConfig(path: path))

import TuistKit

TuistCommand.main()
