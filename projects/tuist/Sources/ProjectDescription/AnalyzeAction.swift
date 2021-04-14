import Foundation

public struct AnalyzeAction: Equatable, Codable {
    public let configurationName: String

    public init(configurationName: String) {
        self.configurationName = configurationName
    }

    public init(config: PresetBuildConfiguration = .release) {
        self.init(configurationName: config.name)
    }
}
