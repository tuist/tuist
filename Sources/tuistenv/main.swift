import Foundation
import TuistEnvKit

import enum TuistSupport.LogOutput

LogOutput.bootstrap()

var registry = CommandRegistry()
registry.run()
