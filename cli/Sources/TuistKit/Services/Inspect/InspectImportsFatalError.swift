import TuistSupport

protocol InspectImportsFatalError: FatalError {}

struct InspectImportsIssue: Equatable {
    let target: String
    let dependencies: Set<String>
}

enum InspectImportsServiceError: InspectImportsFatalError, Equatable {
    case implicitImportsFound([InspectImportsIssue])
    case redundantImportsFound([InspectImportsIssue])

    var description: String {
        switch self {
        case let .implicitImportsFound(issues):
            """
            The following implicit dependencies were found:
            \(
                issues.map { " - \($0.target) implicitly depends on: \($0.dependencies.joined(separator: ", "))" }
                    .joined(separator: "\n")
            )
            """
        case let .redundantImportsFound(issues):
            """
            The following redundant dependencies were found:
            \(
                issues.map { " - \($0.target) redundantly depends on: \($0.dependencies.joined(separator: ", "))" }
                    .joined(separator: "\n")
            )
            """
        }
    }

    var type: ErrorType {
        .abort
    }
}
