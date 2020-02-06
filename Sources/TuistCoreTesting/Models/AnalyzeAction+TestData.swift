import Basic
import Foundation
@testable import TuistCore

public extension AnalyzeAction {
  static func test(configurationName: String = "Beta Release") -> AnalyzeAction {
        AnalyzeAction(configurationName: configurationName)
    }
}
