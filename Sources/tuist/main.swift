import enum Basic.ProcessEnv
import Foundation
import enum TuistSupport.LogOutput

if CommandLine.arguments.contains("--verbose") {
    try? ProcessEnv.setVar("TUIST_VERBOSE", value: "true")
}

LogOutput.bootstrap()

import TuistKit
var registry = CommandRegistry()
registry.run()
