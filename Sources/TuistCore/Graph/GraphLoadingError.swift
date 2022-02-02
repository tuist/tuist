import Foundation
import TSCBasic
import TuistSupport

enum GraphLoadingError: FatalError, Equatable {
    case missingFile(AbsolutePath)
    case targetNotFound(String, AbsolutePath)
    case missingProject(AbsolutePath)
    case manifestNotFound(AbsolutePath)
    case circularDependency([GraphCircularDetectorNode])
    case unexpected(String)

    var type: ErrorType {
        .abort
    }

    var description: String {
        switch self {
        case let .manifestNotFound(path):
            return "Couldn't find manifest at path: '\(path.pathString)'"
        case let .targetNotFound(targetName, path):
            return "Couldn't find target '\(targetName)' at '\(path.pathString)'"
        case let .missingProject(path):
            return "Could not locate project at path: \(path.pathString)"
        case let .missingFile(path):
            return "Couldn't find file at path '\(path.pathString)'"
        case let .unexpected(message):
            return message
        case let .circularDependency(nodes):
            let nodeDescriptions = nodes.map { "\($0.path):\($0.name)" }
            return "Found circular dependency between targets: \(nodeDescriptions.joined(separator: " -> "))"
        }
    }
}
