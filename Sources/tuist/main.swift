import Foundation
import enum TSCBasic.ProcessEnv
import TuistAnalytics
import TuistSupport
import enum TuistSupport.LogOutput

if CommandLine.arguments.contains("--verbose") { try? ProcessEnv.setVar(Constants.EnvironmentVariables.verbose, value: "true") }

LogOutput.bootstrap()
TuistAnalytics.bootstrap()

import TuistKit

TuistCommand.main()
