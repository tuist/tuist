import Foundation
import TuistKit

import enum TuistSupport.LogOutput

LogOutput.bootstrap()

var registry = CommandRegistry()
registry.run()
