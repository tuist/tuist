import Foundation
import TSCBasic
@testable import TuistGraph

public extension AnalyzeAction {
    static func test(configurationName: String = "Beta Release") -> AnalyzeAction {
        AnalyzeAction(configurationName: configurationName)
    }
}
