import Foundation

public struct AnalyzeAction: Equatable, Codable {
    public let configuration: ConfigurationName

    init(configuration: ConfigurationName) {
        self.configuration = configuration
    }

    /// Returns an analyze action.
    /// - Parameter configuration: Configuration used for analyzing.
    /// - Returns: Analyze action.
    public static func analyzeAction(configuration: ConfigurationName) -> AnalyzeAction {
        return AnalyzeAction(configuration: configuration)
    }
}
