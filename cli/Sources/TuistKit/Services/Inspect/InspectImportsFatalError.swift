import TuistSupport

protocol InspectImportsFatalError: FatalError {}

struct InspectImportsIssue: Equatable {
    let target: String
    let dependencies: Set<String>
}

enum InspectImportsServiceError: InspectImportsFatalError, Equatable {
    case issuesFound(implicit: [InspectImportsIssue] = [], redundant: [InspectImportsIssue] = [])

    var description: String {
        switch self {
        case let .issuesFound(implicit, redundant):
            var messages: [String] = []
            if !implicit.isEmpty {
                messages.append(
                    """
                    The following implicit dependencies were found:
                    \(
                        implicit.sorted { $0.target < $1.target }.map { " - \($0.target) implicitly depends on: \($0.dependencies.sorted().joined(separator: ", "))" }
                            .joined(separator: "\n")
                    )
                    """
                )
            }
            if !redundant.isEmpty {
                messages.append(
                    """
                    The following redundant dependencies were found:
                    \(
                        redundant.sorted { $0.target < $1.target }.map { " - \($0.target) redundantly depends on: \($0.dependencies.sorted().joined(separator: ", "))" }
                            .joined(separator: "\n")
                    )
                    """
                )
            }
            return messages.joined(separator: "\n\n")
        }
    }

    var type: ErrorType {
        .abort
    }
}
