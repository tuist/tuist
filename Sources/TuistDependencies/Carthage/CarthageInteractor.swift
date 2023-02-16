import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

// MARK: - Carthage Interactor Errors

enum CarthageInteractorError: FatalError, Equatable {
    /// Thrown when Carthage cannot be found.
    case carthageNotFound
    /// Thrown when `Cartfile` cannot be found in the temporary directory after Carthage installation
    case cartfileNotFound
    /// Thrown when `Cartfile.resolved` cannot be found in temporary directory after Carthage installation.
    case cartfileResolvedNotFound
    /// Thrown when `Carthage/Build` directory cannot be found in temporary directory after Carthage installation.
    case buildDirectoryNotFound

    /// Error type.
    var type: ErrorType {
        switch self {
        case .cartfileNotFound,
             .cartfileResolvedNotFound,
             .buildDirectoryNotFound:
            return .bug
        case .carthageNotFound:
            return .abort
        }
    }

    /// Error description.
    var description: String {
        switch self {
        case .carthageNotFound:
            return """
            Carthage was not found in the environment.
            It's possible that the tool is not installed or hasn't been exposed to your environment."
            """
        case .cartfileNotFound:
            return "The Cartfile file was not found after resolving the dependencies using the Carthage."
        case .cartfileResolvedNotFound:
            return "The Cartfile.resolved lockfile was not found after resolving the dependencies using the Carthage."
        case .buildDirectoryNotFound:
            return "The Carthage/Build directory was not found after resolving the dependencies using the Carthage."
        }
    }
}

// MARK: - Carthage Interacting

public protocol CarthageInteracting {
    /// Installs `Carthage` dependencies
    /// - Parameters:
    ///   - dependenciesDirectory: The path to the directory that contains the `Tuist/Dependencies/` directory.
    ///   - dependencies:  List of dependencies to install using `Carthage`.
    ///   - platforms: List of platforms for which you want to install dependencies.
    ///   - shouldUpdate: Indicates whether dependencies should be updated or fetched based on the `Tuist/Lockfiles/Cartfile.resolved` lockfile.
    /// - Returns: A graph that represents dependencies installed using `Carthage`.
    func install(
        dependenciesDirectory: AbsolutePath,
        dependencies: TuistGraph.CarthageDependencies,
        platforms: Set<TuistGraph.Platform>,
        shouldUpdate: Bool
    ) throws -> TuistCore.DependenciesGraph

    /// Removes all cached `Carthage` dependencies.
    /// - Parameter dependenciesDirectory: The path to the directory that contains the `Tuist/Dependencies/` directory.
    func clean(dependenciesDirectory: AbsolutePath) throws
}

// MARK: - Carthage Interactor

public final class CarthageInteractor: CarthageInteracting {
    private let carthageController: CarthageControlling
    private let carthageGraphGenerator: CarthageGraphGenerating

    public init(
        carthageController: CarthageControlling = CarthageController.shared,
        carthageGraphGenerator: CarthageGraphGenerating = CarthageGraphGenerator()
    ) {
        self.carthageController = carthageController
        self.carthageGraphGenerator = carthageGraphGenerator
    }

    public func install(
        dependenciesDirectory: AbsolutePath,
        dependencies: TuistGraph.CarthageDependencies,
        platforms: Set<TuistGraph.Platform>,
        shouldUpdate: Bool
    ) throws -> TuistCore.DependenciesGraph {
        logger.info("Installing Carthage dependencies.", metadata: .subsection)

        guard carthageController.canUseSystemCarthage() else {
            throw CarthageInteractorError.carthageNotFound
        }

        let pathsProvider = CarthagePathsProvider(dependenciesDirectory: dependenciesDirectory)

        try loadDependencies(pathsProvider: pathsProvider, dependencies: dependencies)

        if shouldUpdate {
            try carthageController.update(
                at: pathsProvider.dependenciesDirectory,
                platforms: platforms,
                printOutput: true
            )
        } else {
            try carthageController.bootstrap(
                at: pathsProvider.dependenciesDirectory,
                platforms: platforms,
                printOutput: true
            )
        }

        try saveDependencies(pathsProvider: pathsProvider)

        let dependenciesGraph = try carthageGraphGenerator
            .generate(at: pathsProvider.destinationCarthageBuildDirectory)

        logger.info("Carthage dependencies installed successfully.", metadata: .subsection)

        return dependenciesGraph
    }

    public func clean(dependenciesDirectory: AbsolutePath) throws {
        let carthageDirectory = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.carthageDirectoryName)
        let cartfileResolvedPath = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.lockfilesDirectoryName)
            .appending(component: Constants.DependenciesDirectory.cartfileResolvedName)

        try FileHandler.shared.delete(carthageDirectory)
        try FileHandler.shared.delete(cartfileResolvedPath)
    }

    // MARK: - Installation

    /// Loads lockfile and dependencies into working directory if they had been saved before.
    private func loadDependencies(pathsProvider: CarthagePathsProvider, dependencies: TuistGraph.CarthageDependencies) throws {
        // copy `Cartfile.resolved` directory from previous run if exist
        if FileHandler.shared.exists(pathsProvider.destinationCartfileResolvedPath) {
            try copy(
                from: pathsProvider.destinationCartfileResolvedPath,
                to: pathsProvider.temporaryCartfileResolvedPath
            )
        }

        // create `Cartfile`
        let cartfileContent = dependencies.cartfileValue()
        let cartfilePath = pathsProvider.temporaryCartfilePath
        try FileHandler.shared.createFolder(cartfilePath.removingLastComponent())
        try FileHandler.shared.write(cartfileContent, path: cartfilePath, atomically: true)

        logger.debug("Cartfile:", metadata: .subsection)
        logger.debug("\(cartfileContent)")
    }

    /// Saves lockfile resolved dependencies in `Tuist/Dependencies` directory.
    private func saveDependencies(pathsProvider: CarthagePathsProvider) throws {
        guard FileHandler.shared.exists(pathsProvider.temporaryCartfilePath) else {
            throw CarthageInteractorError.cartfileNotFound
        }

        guard FileHandler.shared.exists(pathsProvider.temporaryCartfileResolvedPath) else {
            throw CarthageInteractorError.cartfileResolvedNotFound
        }
        guard FileHandler.shared.exists(pathsProvider.destinationCarthageBuildDirectory) else {
            throw CarthageInteractorError.buildDirectoryNotFound
        }

        try copy(
            from: pathsProvider.temporaryCartfilePath,
            to: pathsProvider.destinationCartfilePath
        )

        try copy(
            from: pathsProvider.temporaryCartfileResolvedPath,
            to: pathsProvider.destinationCartfileResolvedPath
        )

        // remove temporary files
        try? FileHandler.shared.delete(pathsProvider.temporaryCartfilePath)
        try? FileHandler.shared.delete(pathsProvider.temporaryCartfileResolvedPath)
    }

    // MARK: - Helpers

    private func copy(from fromPath: AbsolutePath, to toPath: AbsolutePath) throws {
        if FileHandler.shared.exists(toPath) {
            try FileHandler.shared.replace(toPath, with: fromPath)
        } else {
            try FileHandler.shared.createFolder(toPath.removingLastComponent())
            try FileHandler.shared.copy(from: fromPath, to: toPath)
        }
    }
}

// MARK: - Models

private struct CarthagePathsProvider {
    let dependenciesDirectory: AbsolutePath

    let destinationCartfilePath: AbsolutePath
    let destinationCartfileResolvedPath: AbsolutePath
    let destinationCarthageDirectory: AbsolutePath
    let destinationCarthageBuildDirectory: AbsolutePath

    let temporaryCartfilePath: AbsolutePath
    let temporaryCartfileResolvedPath: AbsolutePath

    init(dependenciesDirectory: AbsolutePath) {
        self.dependenciesDirectory = dependenciesDirectory

        destinationCartfilePath = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.carthageDirectoryName)
            .appending(component: Constants.DependenciesDirectory.cartfileName)
        destinationCartfileResolvedPath = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.lockfilesDirectoryName)
            .appending(component: Constants.DependenciesDirectory.cartfileResolvedName)
        destinationCarthageDirectory = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.carthageDirectoryName)
        destinationCarthageBuildDirectory = destinationCarthageDirectory
            .appending(component: "Build")

        temporaryCartfilePath = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.cartfileName)
        temporaryCartfileResolvedPath = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.cartfileResolvedName)
    }
}
