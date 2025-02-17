import Foundation

/// Graph to be sent with the run
public struct RunGraph: Codable, Equatable {
    public let name: String
    public let projects: [RunProject]

    public init(
        name: String,
        projects: [RunProject]
    ) {
        self.name = name
        self.projects = projects
    }
}
