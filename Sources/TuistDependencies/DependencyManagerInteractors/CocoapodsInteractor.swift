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

public protocol CocoapodsInteracting {
}

// MARK: - Cocoapods Interactor

#warning("TODO: Add unit test!")
public final class CocoapodsInteractor: CocoapodsInteracting {
    public init() { }
    
    public func install(at path: AbsolutePath, method: InstallDependenciesMethod) throws {
        throw CocoapodsInteractorError.unimplemented
    }
}
