import TuistLogging
import TuistSupport

struct InspectImportsIssue: Comparable {
    let target: String
    let dependencies: Set<String>

    static func < (lhs: InspectImportsIssue, rhs: InspectImportsIssue) -> Bool {
        if lhs.target != rhs.target {
            return lhs.target < rhs.target
        }
        return lhs.dependencies.sorted().lexicographicallyPrecedes(rhs.dependencies.sorted())
    }
}

enum InspectImportsServiceError: FatalError, Equatable {
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
                        implicit.sorted()
                            .map { " - \($0.target) implicitly depends on: \($0.dependencies.sorted().joined(separator: ", "))" }
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
                        redundant.sorted()
                            .map { " - \($0.target) redundantly depends on: \($0.dependencies.sorted().joined(separator: ", "))" }
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
