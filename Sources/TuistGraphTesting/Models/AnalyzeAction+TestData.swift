import Foundation
import TSCBasic
@testable import TuistGraph

extension AnalyzeAction {
    public static func test(configurationName: String = "Beta Release") -> AnalyzeAction {
        AnalyzeAction(configurationName: configurationName)
    }
}
