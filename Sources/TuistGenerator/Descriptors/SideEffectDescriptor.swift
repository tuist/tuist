import Basic
import Foundation
import XcodeProj

/// Generation Side Effect
public enum SideEffect {
    /// Create / Remove a file
    case file(GeneratedFile)

    /// Perform a command
    case command(GeneratedCommand)
}

public struct GeneratedFile {
    public enum State {
        case present
        case absent
    }

    public var path: AbsolutePath
    public var contents: Data?
    public var state: State

    public init(path: AbsolutePath,
                contents: Data? = nil,
                state: GeneratedFile.State = .present) {
        self.path = path
        self.contents = contents
        self.state = state
    }
}

public struct GeneratedCommand {
    public var command: [String]

    public init(command: [String]) {
        self.command = command
    }
}
