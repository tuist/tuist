import Foundation
import TuistEnvKit
import TuistSupport

try TuistSupport.Environment.shared.bootstrap()
LogOutput.bootstrap()

TuistCommand.main()
