import Foundation

public struct AnalyzeAction: Equatable, Codable, Sendable {
    // MARK: - Attributes

    public let configurationName: String

    // MARK: - Init

    public init(configurationName: String) {
        self.configurationName = configurationName
    }
}

#if DEBUG
    extension AnalyzeAction {
        public static func test(configurationName: String = "Beta Release") -> AnalyzeAction {
            AnalyzeAction(configurationName: configurationName)
        }
    }
#endif
