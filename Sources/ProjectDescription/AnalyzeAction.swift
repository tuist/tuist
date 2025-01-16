/// An action that analyzes the built products.
///
/// It's initialized with the `.analyzeAction` static method
public struct AnalyzeAction: Equatable, Codable, Sendable {
    /// Indicates the build configuration the product should be analyzed with.
    public var configuration: ConfigurationName

    /// Returns an analyze action.
    /// - Parameter configuration: Indicates the build configuration the product should be analyzed with.
    /// - Returns: Analyze action.
    public static func analyzeAction(configuration: ConfigurationName) -> AnalyzeAction {
        AnalyzeAction(configuration: configuration)
    }
}
