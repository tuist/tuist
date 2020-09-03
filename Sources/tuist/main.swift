import Foundation
import enum TSCBasic.ProcessEnv
import TuistAsyncQueue
import TuistSupport
import enum TuistSupport.LogOutput

if CommandLine.arguments.contains("--verbose") { try? ProcessEnv.setVar(Constants.EnvironmentVariables.verbose, value: "true") }

LogOutput.bootstrap()

import TuistKit

try AsyncQueue.run {
    TuistCommand.main()
}
