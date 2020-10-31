import TSCBasic
import TuistSupport

// MARK: - Cocoapods Interactor Errors

public enum CocoapodsInteractorError: FatalError {
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
            return "Cocoapods is not supported yet. We are being worked on and it'll be available soon."
        }
    }
}

// MARK: - Cocoapods Interacting

public protocol CocoapodsInteracting: DependencyManagerInteracting {
}

// MARK: - Cocoapods Interactor

public final class CocoapodsInteractor: CocoapodsInteracting {
    public var isAvailable = false
    
    public init() { }
    
    public func install(method: InstallDependenciesMethod) throws {
        throw CocoapodsInteractorError.unimplemented
    }
}
