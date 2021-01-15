import Foundation

public struct AnalyzeAction: Equatable {
    // MARK: - Attributes

    public let configurationName: String

    // MARK: - Init

    public init(configurationName: String) {
        self.configurationName = configurationName
    }
}
