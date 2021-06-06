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
    /// Installs `CocoaPods` dependencies.
    /// - Parameters:
    ///   - dependenciesDirectory: The path to the directory that contains the `Tuist/Dependencies/` directory.
    ///   - shouldUpdate: Indicates whether dependencies should be updated or fetched based on the `Tuist/Lockfiles/Podfile.lock` lockfile.
    func install(dependenciesDirectory: AbsolutePath, shouldUpdate: Bool) throws

    /// Removes all cached `CocoaPods` dependencies.
    /// - Parameter dependenciesDirectory: The path to the directory that contains the `Tuist/Dependencies/` directory.
    func clean(dependenciesDirectory: AbsolutePath) throws
}

// MARK: - Cocoapods Interactor

public final class CocoaPodsInteractor: CocoaPodsInteracting {
    public init() {}

    public func install(dependenciesDirectory _: AbsolutePath, shouldUpdate _: Bool) throws {
        throw CocoaPodsInteractorError.unimplemented
    }

    public func clean(dependenciesDirectory _: AbsolutePath) throws {
        throw CocoaPodsInteractorError.unimplemented
    }
}
