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

    // Custom equatable to ignore ordering of circular dependency
    public static func == (lhs: GraphLoadingError, rhs: GraphLoadingError) -> Bool {
        switch (lhs, rhs) {
        case let (.missingFile(lhsPath), .missingFile(rhsPath)):
            return lhsPath == rhsPath
        case let (.targetNotFound(lhsName, lhsPath), .targetNotFound(rhsName, rhsPath)):
            return lhsPath == rhsPath && lhsName == rhsName
        case let (.missingProject(lhsPath), .missingProject(rhsPath)):
            return lhsPath == rhsPath
        case let (.manifestNotFound(lhsPath), .manifestNotFound(rhsPath)):
            return lhsPath == rhsPath
        case let (.unexpected(lhsMessage), .unexpected(rhsMessage)):
            return lhsMessage == rhsMessage
        case let (.circularDependency(lhsNodes), .circularDependency(rhsNodes)):
            return Set(lhsNodes) == Set(rhsNodes)
        default:
            return false
        }
    }
}
