import Foundation

// MARK: - Setup

/// Setup represents a list of actions that configures the environment for the project to work.
/// Used by `tuist up` command.
public class Setup: Codable {

    public let actions: [Up]

    public init(_ actions: [Up]) {
        self.actions = actions
        dumpIfNeeded(self)
    }
}
