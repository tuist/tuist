import TSCBasic
import TuistSupport

// MARK: - Swift Package Manager Interactor Error

public enum SwiftPackageManagerInteractorError: FatalError {
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
            return "Swift Package Manager is not supported yet. It's being worked on and it'll be available soon."
        }
    }
}

// MARK: - Swift Package Manager Interacting

public protocol SwiftPackageManagerInteracting {
    /// Fetches `Swift Package Manager` dependencies.
    /// - Parameter dependenciesDirectoryPath: The path to the directory that contains the `Tuist/Dependencies/` directory.
    func fetch(dependenciesDirectory: AbsolutePath) throws
}

// MARK: - Swift Package Manager Interactor

public final class SwiftPackageManagerInteractor: SwiftPackageManagerInteracting {
    public init() {}

    public func fetch(dependenciesDirectory _: AbsolutePath) throws {
        throw SwiftPackageManagerInteractorError.unimplemented
    }
}
