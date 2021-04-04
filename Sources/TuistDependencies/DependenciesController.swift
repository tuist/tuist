import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

// MARK: - Dependencies Controller Error

enum DependenciesControllerError: FatalError {
    /// Thrown when platforms for dependencies to install are not determined in `Dependencies.swift`.
    case noPlatforms
    
    /// Error type.
    var type: ErrorType {
        switch self {
        case .noPlatforms:
            return .abort
        }
    }
    
    // Error description.
    var description: String {
        switch self {
        case .noPlatforms:
            return "Platforms were not determined. Select platforms in `Dependencies.swift` manifest file."
        }
    }
}

// MARK: - Dependencies Controlling

/// `DependenciesControlling` controls:
///     1. Fetching/updating dependencies defined in `./Tuist/Dependencies.swift` by running appropriate dependencies managers (`Cocoapods`, `Carthage`, `SPM`).
///     2. Compiling fetched/updated depedencies into `.framework.`/`.xcframework.`.
///     3. Saving compiled frameworks under `./Tuist/Dependencies/*`.
///     4. Generating dependencies graph under `./Tuist/Dependencies/graph.json`.
public protocol DependenciesControlling {
    /// Fetches dependencies.
    /// - Parameter path: Directory whose project's dependencies will be installed.
    /// - Parameter dependencies: List of dependencies to intall.
    func fetch(at path: AbsolutePath, dependencies: Dependencies) throws
}

// MARK: - Dependencies Controller

public final class DependenciesController: DependenciesControlling {
    private let carthageInteractor: CarthageInteracting
    private let cocoaPodsInteractor: CocoaPodsInteracting
    private let swiftPackageManagerInteractor: SwiftPackageManagerInteracting

    public init(
        carthageInteractor: CarthageInteracting = CarthageInteractor(),
        cocoaPodsInteractor: CocoaPodsInteracting = CocoaPodsInteractor(),
        swiftPackageManagerInteractor: SwiftPackageManagerInteracting = SwiftPackageManagerInteractor()
    ) {
        self.carthageInteractor = carthageInteractor
        self.cocoaPodsInteractor = cocoaPodsInteractor
        self.swiftPackageManagerInteractor = swiftPackageManagerInteractor
    }

    public func fetch(at path: AbsolutePath, dependencies: Dependencies) throws {
        let dependenciesDirectory = path
            .appending(component: Constants.tuistDirectoryName)
            .appending(component: Constants.DependenciesDirectory.name)
        let platforms = dependencies.platforms

        guard !platforms.isEmpty else {
            throw DependenciesControllerError.noPlatforms
        }

        if let carthageDepedencies = dependencies.carthage, !carthageDepedencies.dependencies.isEmpty {
            try carthageInteractor.fetch(
                dependenciesDirectory: dependenciesDirectory,
                dependencies: carthageDepedencies,
                platforms: platforms
            )
        } else {
            try carthageInteractor.clean(dependenciesDirectory: dependenciesDirectory)
        }

        if let swiftPackageManagerDependencies = dependencies.swiftPackageManager, !swiftPackageManagerDependencies.packages.isEmpty {
            try swiftPackageManagerInteractor.fetch(
                dependenciesDirectory: dependenciesDirectory,
                dependencies: swiftPackageManagerDependencies,
                platforms: platforms
            )
        } else {
            try swiftPackageManagerInteractor.clean(dependenciesDirectory: dependenciesDirectory)
        }
    }
}
