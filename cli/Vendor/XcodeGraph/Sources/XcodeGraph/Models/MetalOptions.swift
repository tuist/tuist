import Foundation

public struct MetalOptions: Equatable, Codable, Sendable {
    public var apiValidation: Bool
    public var shaderValidation: Bool
    public var showGraphicsOverview: Bool
    public var logGraphicsOverview: Bool

    public init(
        apiValidation: Bool = true,
        shaderValidation: Bool = false,
        showGraphicsOverview: Bool = false,
        logGraphicsOverview: Bool = false
    ) {
        self.apiValidation = apiValidation
        self.shaderValidation = shaderValidation
        self.showGraphicsOverview = showGraphicsOverview
        self.logGraphicsOverview = logGraphicsOverview
    }
}
