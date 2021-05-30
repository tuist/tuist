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
    /// - Parameter path: Directory whose project's dependencies will be fetched.
    /// - Parameter dependencies: List of dependencies to fetch.
    /// - Parameter swiftVersion: The specified version of Swift. If `nil` is passed then the environment’s version will be used.
    func fetch(
        at path: AbsolutePath,
        dependencies: Dependencies,
        swiftVersion: String?
    ) throws

    /// Updates dependencies.
    /// - Parameters:
    ///   - path: Directory whose project's dependencies will be updated.
    ///   - dependencies: List of dependencies to update.
    ///   - swiftVersion: The specified version of Swift. If `nil` is passed then will use the environment’s version will be used.
    func update(
        at path: AbsolutePath,
        dependencies: Dependencies,
        swiftVersion: String?
    ) throws
}

// MARK: - Dependencies Controller

public final class DependenciesController: DependenciesControlling {
    private let carthageInteractor: CarthageInteracting
    private let cocoaPodsInteractor: CocoaPodsInteracting
    private let swiftPackageManagerInteractor: SwiftPackageManagerInteracting
    private let dependenciesGraphController: DependenciesGraphControlling

    public init(
        carthageInteractor: CarthageInteracting = CarthageInteractor(),
        cocoaPodsInteractor: CocoaPodsInteracting = CocoaPodsInteractor(),
        swiftPackageManagerInteractor: SwiftPackageManagerInteracting = SwiftPackageManagerInteractor(),
        dependenciesGraphController: DependenciesGraphControlling = DependenciesGraphController()
    ) {
        self.carthageInteractor = carthageInteractor
        self.cocoaPodsInteractor = cocoaPodsInteractor
        self.swiftPackageManagerInteractor = swiftPackageManagerInteractor
        self.dependenciesGraphController = dependenciesGraphController
    }

    public func fetch(
        at path: AbsolutePath,
        dependencies: Dependencies,
        swiftVersion: String?
    ) throws {
        try install(
            at: path,
            dependencies: dependencies,
            shouldUpdate: false,
            swiftVersion: swiftVersion
        )
    }

    public func update(
        at path: AbsolutePath,
        dependencies: Dependencies,
        swiftVersion: String?
    ) throws {
        try install(
            at: path,
            dependencies: dependencies,
            shouldUpdate: true,
            swiftVersion: swiftVersion
        )
    }
    
    // MARK: - Helpers
    
    private func install(
        at path: AbsolutePath,
        dependencies: Dependencies,
        shouldUpdate: Bool,
        swiftVersion: String?
    ) throws {
        let dependenciesDirectory = path
            .appending(component: Constants.tuistDirectoryName)
            .appending(component: Constants.DependenciesDirectory.name)
        let platforms = dependencies.platforms

        guard !platforms.isEmpty else {
            throw DependenciesControllerError.noPlatforms
        }
        
        #warning("laxmorek: Refactor me!")
        var dependenciesGraph: DependenciesGraph?
        
        if let carthageDepedencies = dependencies.carthage, !carthageDepedencies.dependencies.isEmpty {
            dependenciesGraph = try carthageInteractor.install(
                dependenciesDirectory: dependenciesDirectory,
                dependencies: carthageDepedencies,
                platforms: platforms,
                shouldUpdate: shouldUpdate
            )
        } else {
            try carthageInteractor.clean(dependenciesDirectory: dependenciesDirectory)
        }

        if let swiftPackageManagerDependencies = dependencies.swiftPackageManager, !swiftPackageManagerDependencies.packages.isEmpty {
            try swiftPackageManagerInteractor.install(
                dependenciesDirectory: dependenciesDirectory,
                dependencies: swiftPackageManagerDependencies,
                shouldUpdate: shouldUpdate,
                swiftToolsVersion: swiftVersion
            )
        } else {
            try swiftPackageManagerInteractor.clean(dependenciesDirectory: dependenciesDirectory)
        }
        
        if let dependenciesGraph = dependenciesGraph {
            try dependenciesGraphController.save(dependenciesGraph, at: path)
        } else {
            #warning("laxmorek: no graph, remove already cached?")
        }
    }
}
