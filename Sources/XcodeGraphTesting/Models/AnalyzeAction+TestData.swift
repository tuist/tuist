import Foundation
import Path
@testable import XcodeGraph

extension AnalyzeAction {
    public static func test(configurationName: String = "Beta Release") -> AnalyzeAction {
        AnalyzeAction(configurationName: configurationName)
    }
}
