import Foundation
import Testing
@testable import SwifterPMCore

let exitCode: CInt = await Testing.__swiftPMEntryPoint()
Foundation.exit(exitCode)
