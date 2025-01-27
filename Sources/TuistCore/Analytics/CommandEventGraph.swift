import Foundation

/// Graph to be sent with the command event
public struct CommandEventGraph: Codable, Equatable {
    public let name: String
    public let projects: [CommandEventProject]

    public init(
        name: String,
        projects: [CommandEventProject]
    ) {
        self.name = name
        self.projects = projects
    }
}
