import Foundation

/// Options to configure scheme metal options for run and test actions.
public struct MetalOptions: Equatable, Codable, Sendable {
    /// API Validation
    public var apiValidation: Bool

    /// Shader Validation
    public var shaderValidation: Bool

    /// Shows graphics overview
    public var showGraphicsOverview: Bool

    /// Log graphics overview
    public var logGraphicsOverview: Bool

    public static func options(
        apiValidation: Bool = true,
        shaderValidation: Bool = false,
        showGraphicsOverview: Bool = false,
        logGraphicsOverview: Bool = false
    ) -> MetalOptions {
        return MetalOptions(
            apiValidation: apiValidation,
            shaderValidation: shaderValidation,
            showGraphicsOverview: showGraphicsOverview,
            logGraphicsOverview: logGraphicsOverview
        )
    }
}
