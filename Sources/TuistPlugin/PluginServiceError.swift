import TSCBasic
import TuistSupport

/// Errors thrown by `PluginService`.
public enum PluginServiceError: FatalError {
    case configNotFound(AbsolutePath)

    public var description: String {
        switch self {
        case let .configNotFound(path):
            return "Unable to load plugins, Config.swift manifest not located at \(path)"
        }
    }

    public var type: ErrorType {
        switch self {
        case .configNotFound:
            return .abort
        }
    }
}
