import TSCBasic
import TuistSupport

// MARK: - SPM Interactor Error

public enum SPMInteractorError: FatalError {
    case unimplemented

    /// Error type.
    public var type: ErrorType {
        switch self {
        case .unimplemented:
            return .abort
        }
    }

    /// Description.
    public var description: String {
        switch self {
        case .unimplemented:
            return "Swift Package Manager is not supported yet. We are being worked on and it'll be available soon."
        }
    }
}

// MARK: - SPM Interacting

public protocol SPMInteracting: DependencyManagerInteracting {
}

// MARK: - SPM Interactor

public final class SPMInteractor: SPMInteracting {
    public let isAvailable = false
    
    public init() { }
    
    public func install(method: InstallDependenciesMethod) throws {
        throw SPMInteractorError.unimplemented
    }
}
