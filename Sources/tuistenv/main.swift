import Foundation
import TSCBasic
import TuistEnvKit
import TuistSupport

if CommandLine.arguments.contains("--generate-completion-script") {
    try? ProcessEnv.setVar(Constants.EnvironmentVariables.silent, value: "true")
}

try TuistSupport.Environment.shared.bootstrap()
LogOutput.bootstrap()

TuistCommand.main()
