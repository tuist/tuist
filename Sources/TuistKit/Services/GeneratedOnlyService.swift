import TuistCore
import TuistSupport

enum GeneratedOnlyServiceError: FatalError {
    case xcodeProjectNotSupported(command: String)

    var description: String {
        switch self {
        case .xcodeProjectNotSupported:
            return "Non generated Xcode projects are not supported by the `build` command."
        }
    }

    var type: ErrorType {
        switch self {
        case .xcodeProjectNotSupported:
            return .abort
        }
    }
}

func validateIsGeneratedProject(config: Tuist, command: String) throws {
    if !config.project.isGenerated {
        throw GeneratedOnlyServiceError.xcodeProjectNotSupported(command: command)
    }
}
