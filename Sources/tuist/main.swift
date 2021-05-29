import Foundation
import enum TSCBasic.ProcessEnv
import TuistAnalytics
import TuistSupport

if CommandLine.arguments.contains("--verbose") { try? ProcessEnv.setVar(Constants.EnvironmentVariables.verbose, value: "true") }

TuistSupport.LogOutput.bootstrap()
TuistAnalytics.bootstrap()

import TuistKit

TuistCommand.main()
