import Foundation

/// An action that analyzes the built products.
public struct AnalyzeAction: Equatable, Codable {
    /// Indicates the build configuration the product should be analyzed with.
    public var configuration: ConfigurationName
}
