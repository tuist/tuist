import Foundation
import TSCBasic
import TuistEnvKit
import TuistSupport

if CommandLine.arguments.contains("--generate-completion-script") {
    try? ProcessEnv.setVar(Constants.EnvironmentVariables.silent, value: "true")
}

LogOutput.bootstrap()

TuistCommand.main()
