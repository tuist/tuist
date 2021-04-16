import Foundation

public struct AnalyzeAction: Equatable, Codable {
    // MARK: - Attributes

    public let configurationName: String

    // MARK: - Init

    public init(configurationName: String) {
        self.configurationName = configurationName
    }
}
