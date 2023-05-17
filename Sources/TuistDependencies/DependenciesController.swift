import ProjectDescription
import TSCBasic
import TSCUtility
import TuistCore
import TuistGraph
import TuistSupport

// MARK: - Dependencies Controller Error

enum DependenciesControllerError: FatalError, Equatable {
    /// Thrown when the same dependency is defined more than once.
    case duplicatedDependency(String, [ProjectDescription.TargetDependency], [ProjectDescription.TargetDependency])

    /// Thrown when the same project is defined more than once.
    case duplicatedProject(Path, ProjectDescription.Project, ProjectDescription.Project)

    /// Thrown when platforms for dependencies to install are not determined in `Dependencies.swift`.
    case noPlatforms

    /// Error type.
    var type: ErrorType {
        switch self {
        case .duplicatedDependency, .duplicatedProject, .noPlatforms:
            return .abort
        }
    }

    // Error description.
    var description: String {
        switch self {
        case let .duplicatedDependency(name, first, second):
            return """
            The \(name) dependency is defined twice across different dependency managers:
            First: \(first)
            Second: \(second)
            """
        case let .duplicatedProject(name, first, second):
            return """
            The \(name) project is defined twice across different dependency managers:
            First: \(first)
            Second: \(second)
            """
        case .noPlatforms:
            return "Platforms were not determined. Select platforms in `Dependencies.swift` manifest file."
        }
    }
}

// MARK: - Dependencies Controlling

/// `DependenciesControlling` controls:
///     1. Fetching/updating dependencies defined in `./Tuist/Dependencies.swift` by running appropriate dependencies managers (for example, `Carthage` or `SPM`).
///     2. Compiling fetched/updated dependencies into `.framework.`/`.xcframework.`.
///     3. Saving compiled frameworks under `./Tuist/Dependencies/*`.
///     4. Generating dependencies graph under `./Tuist/Dependencies/graph.json`.
public protocol DependenciesControlling {
    /// Fetches dependencies.
    /// - Parameter path: Directory where project's dependencies will be fetched.
    /// - Parameter dependencies: List of dependencies to fetch.
    /// - Parameter swiftVersion: The specified version of Swift. If `nil` is passed then the environment’s version will be used.
    func fetch(
        at path: AbsolutePath,
        dependencies: TuistGraph.Dependencies,
        swiftVersion: TSCUtility.Version?
    ) throws -> TuistCore.DependenciesGraph

    /// Updates dependencies.
    /// - Parameters:
    ///   - path: Directory where project's dependencies will be updated.
    ///   - dependencies: List of dependencies to update.
    ///   - swiftVersion: The specified version of Swift. If `nil` is passed then will use the environment’s version will be used.
    func update(
        at path: AbsolutePath,
        dependencies: TuistGraph.Dependencies,
        swiftVersion: TSCUtility.Version?
    ) throws -> TuistCore.DependenciesGraph

    /// Save dependencies graph.
    /// - Parameters:
    ///   - dependenciesGraph: The dependencies graph to be saved.
    ///   - path: Directory where dependencies graph will be saved.
    func save(
        dependenciesGraph: TuistGraph.DependenciesGraph,
        to path: AbsolutePath
    ) throws
}

// MARK: - Dependencies Controller

public final class DependenciesController: DependenciesControlling {
    private let carthageInteractor: CarthageInteracting
    private let swiftPackageManagerInteractor: SwiftPackageManagerInteracting
    private let dependenciesGraphController: DependenciesGraphControlling

    public init(
        carthageInteractor: CarthageInteracting = CarthageInteractor(),
        swiftPackageManagerInteractor: SwiftPackageManagerInteracting = SwiftPackageManagerInteractor(),
        dependenciesGraphController: DependenciesGraphControlling = DependenciesGraphController()
    ) {
        self.carthageInteractor = carthageInteractor
        self.swiftPackageManagerInteractor = swiftPackageManagerInteractor
        self.dependenciesGraphController = dependenciesGraphController
    }

    public func fetch(
        at path: AbsolutePath,
        dependencies: TuistGraph.Dependencies,
        swiftVersion: TSCUtility.Version?
    ) throws -> TuistCore.DependenciesGraph {
        try install(
            at: path,
            dependencies: dependencies,
            shouldUpdate: false,
            swiftVersion: swiftVersion
        )
    }

    public func update(
        at path: AbsolutePath,
        dependencies: TuistGraph.Dependencies,
        swiftVersion: TSCUtility.Version?
    ) throws -> TuistCore.DependenciesGraph {
        try install(
            at: path,
            dependencies: dependencies,
            shouldUpdate: true,
            swiftVersion: swiftVersion
        )
    }

    public func save(
        dependenciesGraph: TuistGraph.DependenciesGraph,
        to path: AbsolutePath
    ) throws {
        try dependenciesGraphController.save(dependenciesGraph, to: path)
    }

    // MARK: - Helpers

    private func install(
        at path: AbsolutePath,
        dependencies: TuistGraph.Dependencies,
        shouldUpdate: Bool,
        swiftVersion: TSCUtility.Version?
    ) throws -> TuistCore.DependenciesGraph {
        let dependenciesDirectory = path
            .appending(component: Constants.tuistDirectoryName)
            .appending(component: Constants.DependenciesDirectory.name)
        let platforms = dependencies.platforms

        guard !platforms.isEmpty else {
            throw DependenciesControllerError.noPlatforms
        }

        var dependenciesGraph = TuistCore.DependenciesGraph.none

        if let carthageDependencies = dependencies.carthage, !carthageDependencies.dependencies.isEmpty {
            let carthageDependenciesGraph = try carthageInteractor.install(
                dependenciesDirectory: dependenciesDirectory,
                dependencies: carthageDependencies,
                platforms: platforms,
                shouldUpdate: shouldUpdate
            )
            dependenciesGraph = try dependenciesGraph.merging(with: carthageDependenciesGraph)
        } else {
            try carthageInteractor.clean(dependenciesDirectory: dependenciesDirectory)
        }

        if let swiftPackageManagerDependencies = dependencies.swiftPackageManager,
           !swiftPackageManagerDependencies.packages.isEmpty
        {
            let swiftPackageManagerDependenciesGraph = try swiftPackageManagerInteractor.install(
                dependenciesDirectory: dependenciesDirectory,
                dependencies: swiftPackageManagerDependencies,
                platforms: platforms,
                shouldUpdate: shouldUpdate,
                swiftToolsVersion: swiftVersion
            )
            dependenciesGraph = try dependenciesGraph.merging(with: swiftPackageManagerDependenciesGraph)
        } else {
            try swiftPackageManagerInteractor.clean(dependenciesDirectory: dependenciesDirectory)
        }

        return dependenciesGraph
    }
}

extension TuistCore.DependenciesGraph {
    public func merging(with other: Self) throws -> Self {
        var mergedExternalDependencies: [ProjectDescription.Platform: [String: [ProjectDescription.TargetDependency]]] =
            externalDependencies

        try other.externalDependencies.forEach { platform, otherPlatformDependencies in
            try otherPlatformDependencies.forEach { name, dependency in
                if let alreadyPresent = mergedExternalDependencies[platform]?[name] {
                    throw DependenciesControllerError.duplicatedDependency(name, alreadyPresent, dependency)
                }
                mergedExternalDependencies[platform, default: [:]][name] = dependency
            }
        }

        let mergedExternalProjects = try other.externalProjects.reduce(into: externalProjects) { result, entry in
            if let alreadyPresent = result[entry.key] {
                throw DependenciesControllerError.duplicatedProject(entry.key, alreadyPresent, entry.value)
            }
            result[entry.key] = entry.value
        }

        return .init(externalDependencies: mergedExternalDependencies, externalProjects: mergedExternalProjects)
    }
}
