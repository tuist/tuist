import Foundation

/// Graph to be sent with the run
public struct RunGraph: Codable, Equatable {
    public let name: String
    public let projects: [RunProject]
    public let binaryBuildDuration: TimeInterval?

    public init(
        name: String,
        projects: [RunProject],
        binaryBuildDuration: TimeInterval?
    ) {
        self.name = name
        self.projects = projects
        self.binaryBuildDuration = binaryBuildDuration
    }
}
