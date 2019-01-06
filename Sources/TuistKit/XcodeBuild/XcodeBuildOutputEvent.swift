import Foundation

/// Enum that defines all possible events delivered through
/// the xcodebuild output.
enum XcodeBuildOutputEvent: Equatable {
    /// Analyze event.
    case analyze(filePath: String, name: String)

    /// Build a project target event.
    case buildTarget(target: String, project: String, configuration: String)

    /// Aggregate target event.
    case aggregateTarget(target: String, project: String, configuration: String)

    /// Analyze target event.
    case analyzeTarget(target: String, project: String, configuration: String)

    /// Check dependencies between targets event.
    case checkDependencies

    /// Shell command event. Output when Xcode runs a shell script build phase.
    case shellCommand(path: String, arguments: String)

    /// Clean remove event.
    case cleanRemove

    /// Clean target event.
    case cleanTarget(target: String, project: String, configuration: String)

    /// Code sign event where the path points to the file being code signed.
    case codeSign(path: String)

    /// Compares two instances of XcodeBuildOutputEvent and returns true if both
    /// are equal.
    ///
    /// - Parameters:
    ///   - lhs: First instance to be compared.
    ///   - rhs: Second instance to be compared.
    /// - Returns: True if the two instances are equal.
    static func == (lhs: XcodeBuildOutputEvent, rhs: XcodeBuildOutputEvent) -> Bool {
        switch (lhs, rhs) {
        case let (.analyze(lhsFilePath, lhsName), .analyze(rhsFilePath, rhsName)):
            return lhsFilePath == rhsFilePath &&
                lhsName == rhsName
        case let (.buildTarget(lhsTarget, lhsProject, lhsConfiguration), .buildTarget(rhsTarget, rhsProject, rhsConfiguration)):
            return lhsTarget == rhsTarget &&
                lhsProject == rhsProject &&
                lhsConfiguration == rhsConfiguration
        case let (.aggregateTarget(lhsTarget, lhsProject, lhsConfiguration), .aggregateTarget(rhsTarget, rhsProject, rhsConfiguration)):
            return lhsTarget == rhsTarget &&
                lhsProject == rhsProject &&
                lhsConfiguration == rhsConfiguration
        case let (.analyzeTarget(lhsTarget, lhsProject, lhsConfiguration), .analyzeTarget(rhsTarget, rhsProject, rhsConfiguration)):
            return lhsTarget == rhsTarget &&
                lhsProject == rhsProject &&
                lhsConfiguration == rhsConfiguration
        case (.checkDependencies, .checkDependencies):
            return true
        case let (.shellCommand(lhsPath, lhsArguments), .shellCommand(rhsPath, rhsArguments)):
            return lhsPath == rhsPath && lhsArguments == rhsArguments
        case (.cleanRemove, .cleanRemove):
            return true
        case let (.cleanTarget(lhsTarget, lhsProject, lhsConfiguration), .cleanTarget(rhsTarget, rhsProject, rhsConfiguration)):
            return lhsTarget == rhsTarget &&
                lhsProject == rhsProject &&
                lhsConfiguration == rhsConfiguration
        case let (.codeSign(lhsPath), .codeSign(rhsPath)):
            return lhsPath == rhsPath
        default:
            return false
        }
    }
}
