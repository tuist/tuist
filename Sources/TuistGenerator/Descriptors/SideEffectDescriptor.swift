import Basic
import Foundation
import XcodeProj

public enum GeneratedSideEffect {
    case file(GeneratedFile)
    case delete(AbsolutePath)
    case command(GeneratedCommand)
}

public struct GeneratedFile {
    public var path: AbsolutePath
    public var contents: Data
}

public struct GeneratedCommand {
    public var command: [String]
}
