import TSCBasic
import TuistSupport
import TuistGraph

//// MARK: - Swift Package Manager Interactor Error
//
//public enum SwiftPackageManagerInteractorError: FatalError {
//
//}

// MARK: - Swift Package Manager Interacting

public protocol SwiftPackageManagerInteracting {
    /// Fetches `Swift Package Manager` dependencies.
    /// - Parameter dependenciesDirectory: The path to the directory that contains the `Tuist/Dependencies/` directory.
    /// - Parameter dependencies: List of dependencies to intall using `Swift Package Manager`.
    func fetch(dependenciesDirectory: AbsolutePath, dependencies: SwiftPackageManagerDependencies) throws
}

// MARK: - Swift Package Manager Interactor

public final class SwiftPackageManagerInteractor: SwiftPackageManagerInteracting {
    public init() {}

    public func fetch(dependenciesDirectory: AbsolutePath, dependencies: SwiftPackageManagerDependencies) throws {
        #warning("IMPLEMENT ME")
    }
}
