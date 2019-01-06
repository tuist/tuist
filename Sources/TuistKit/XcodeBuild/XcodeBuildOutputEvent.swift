import Foundation

/// Enum that defines all possible events delivered through
/// the xcodebuild output.
enum XcodeBuildOutputEvent: Equatable {
    /// Analyze event.
    case analyze(filePath: String, name: String)

    /// Build a project target event.
    case buildTarget(target: String, project: String, configuration: String)

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
        default:
            return false
        }
    }
}
