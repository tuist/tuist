import Foundation
import enum Basic.ProcessEnv

if CommandLine.arguments.contains("--verbose") {
    try? ProcessEnv.setVar("TUIST_VERBOSE", value: "true")
}

import enum TuistSupport.LogOutput
LogOutput.bootstrap()

import TuistKit
var registry = CommandRegistry()
registry.run()
