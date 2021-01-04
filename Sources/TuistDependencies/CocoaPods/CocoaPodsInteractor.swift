import TSCBasic
import TuistSupport

// MARK: - CocoaPods Interactor Errors

enum CocoaPodsInteractorError: FatalError {
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
            return "CocoaPods is not supported yet. It's being worked on and it'll be available soon."
        }
    }
}

// MARK: - CocoaPods Interacting

public protocol CocoaPodsInteracting {
    /// Fetches `CocoaPods` dependencies.
    /// - Parameter dependenciesDirectory: The path to the directory that contains the `Tuist/Dependencies/` directory.
    func fetch(dependenciesDirectory: AbsolutePath) throws
}

// MARK: - Cocoapods Interactor

public final class CocoaPodsInteractor: CocoaPodsInteracting {
    public init() {}

    public func fetch(dependenciesDirectory _: AbsolutePath) throws {
        throw CocoaPodsInteractorError.unimplemented
    }
}
