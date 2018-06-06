import Basic
import Foundation

enum ProjectValidationError: FatalError, Equatable {
    case duplicatedTargets([String], AbsolutePath)

    /// Error type.
    var type: ErrorType {
        switch self {
        default:
            return .abort
        }
    }

    /// Error description.
    var description: String {
        switch self {
        case let .duplicatedTargets(targets, projectPath):
            return "Targets \(targets.joined(separator: ", ")) from project at \(projectPath.asString) have duplicates."
        }
    }

    static func == (lhs: ProjectValidationError, rhs: ProjectValidationError) -> Bool {
        switch (lhs, rhs) {
        case let (.duplicatedTargets(lhsTargets, lhsPath), .duplicatedTargets(rhsTargets, rhsPath)):
            return lhsTargets == rhsTargets && lhsPath == rhsPath
        }
    }
}

/// Validates the format of the project.
class ProjectValidator {
    let targetValidator: TargetValidator = TargetValidator()

    func validate(_ project: Project) throws {
        try validateTargets(project: project)
    }

    fileprivate func validateTargets(project: Project) throws {
        try project.targets.forEach(targetValidator.validate)
        try validateNotDuplicatedTargets(project: project)
    }

    fileprivate func validateNotDuplicatedTargets(project: Project) throws {
        let duplicatedTargets = project.targets.map({ $0.name })
            .reduce(into: [String: Int]()) { $0[$1] = ($0[$1] ?? 0) + 1 }
            .filter({ $0.value > 1 })
            .keys
        if duplicatedTargets.count == 0 { return }
        throw ProjectValidationError.duplicatedTargets(Array(duplicatedTargets), project.path)
    }
}
