import TSCBasic
import TuistCore
import TuistSupport

// MARK: - Dependencies Controlling

/// `DependenciesControlling` controls:
///     1. Fetching/updating dependencies defined in `./Tuist/Dependencies.swift` by running appropriate dependencies managers (`Cocoapods`, `Carthage`, `SPM`).
///     2. Compiling fetched/updated depedencies into `.framework.`/`.xcframework.`.
///     3. Saving compiled frameworks under `./Tuist/Dependencies/*`.
///     4. Generating dependencies graph under `./Tuist/Dependencies/graph.json`.
public protocol DependenciesControlling {
    /// Installes dependencies.
    /// - Parameter path: Directory whose project's dependencies will be installed.
    /// - Parameter method: Installation method.
    /// - Parameter carthageDependencies: List of dependencies to intall using `Carthage`.
    func install(
        at path: AbsolutePath,
        method: InstallDependenciesMethod,
        carthageDependencies: [CarthageDependency]
    ) throws
}

// MARK: - Dependencies Controller

#warning("TODO: Add unit test!")
public final class DependenciesController: DependenciesControlling {
    private let carthageInteractor: CarthageInteracting
    private let cocoapodsInteractor: CocoapodsInteracting
    private let spmInteractor: SPMInteracting
    
    public init(
        carthageInteractor: CarthageInteracting = CarthageInteractor(),
        cocoapodsInteractor: CocoapodsInteracting = CocoapodsInteractor(),
        spmInteractor: SPMInteracting = SPMInteractor()
    ) {
        self.carthageInteractor = carthageInteractor
        self.cocoapodsInteractor = cocoapodsInteractor
        self.spmInteractor = spmInteractor
    }
    
    public func install(
        at path: AbsolutePath,
        method: InstallDependenciesMethod,
        carthageDependencies: [CarthageDependency]
    ) throws {
        try carthageInteractor.install(at: path, method: method, dependencies: carthageDependencies)
    }
}
