import RxBlocking
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

// MARK: - Carthage Interactor Errors

enum CarthageInteractorError: FatalError, Equatable {
    /// Thrown when Carthage cannot be found.
    case carthageNotFound
    /// Thrown when `Cartfile.resolved` cannot be found in temporary directory after Carthage installation.
    case cartfileResolvedNotFound
    /// Thrown when `Carthage/Build` directory cannot be found in temporary directory after Carthage installation.
    case buildDirectoryNotFound

    /// Error type.
    var type: ErrorType {
        switch self {
        case .cartfileResolvedNotFound,
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
        dependencies: CarthageDependencies,
        platforms: Set<Platform>,
        shouldUpdate: Bool
    ) throws -> DependenciesGraph

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
        dependencies: CarthageDependencies,
        platforms: Set<Platform>,
        shouldUpdate: Bool
    ) throws -> DependenciesGraph {
        logger.info("Installing Carthage dependencies.", metadata: .subsection)

        // check availability of `carthage`
        guard carthageController.canUseSystemCarthage() else {
            throw CarthageInteractorError.carthageNotFound
        }

        // install depedencies and generate dependencies graph
        let dependenciesGraph: DependenciesGraph = try FileHandler.shared
            .inTemporaryDirectory { temporaryDirectoryPath in
                // prepare paths
                let pathsProvider = CarthagePathsProvider(
                    dependenciesDirectory: dependenciesDirectory,
                    temporaryDirectoryPath: temporaryDirectoryPath
                )

                // prepare for installation
                try loadDependencies(pathsProvider: pathsProvider, dependencies: dependencies)

                // run `Carthage`
                if shouldUpdate {
                    try carthageController.update(
                        at: temporaryDirectoryPath,
                        platforms: platforms
                    )
                } else {
                    try carthageController.bootstrap(
                        at: temporaryDirectoryPath,
                        platforms: platforms
                    )
                }

                // post installation
                try saveDepedencies(pathsProvider: pathsProvider)

                // generate dependencies graph
                return try carthageGraphGenerator
                    .generate(at: pathsProvider.temporaryCarthageBuildDirectory)
            }

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
    private func loadDependencies(pathsProvider: CarthagePathsProvider, dependencies: CarthageDependencies) throws {
        // copy build directory from previous run if exist
        if FileHandler.shared.exists(pathsProvider.destinationCarthageDirectory) {
            try copy(
                from: pathsProvider.destinationCarthageDirectory,
                to: pathsProvider.temporaryCarthageBuildDirectory
            )
        }

        // copy `Cartfile.resolved` directory from previous run if exist
        if FileHandler.shared.exists(pathsProvider.destinationCarfileResolvedPath) {
            try copy(
                from: pathsProvider.destinationCarfileResolvedPath,
                to: pathsProvider.temporaryCarfileResolvedPath
            )
        }

        // create `Cartfile`
        let cartfileContent = dependencies.cartfileValue()
        let cartfilePath = pathsProvider.temporaryDirectoryPath.appending(component: "Cartfile")
        try FileHandler.shared.write(cartfileContent, path: cartfilePath, atomically: true)

        // log
        logger.debug("Cartfile:", metadata: .subsection)
        logger.debug("\(cartfileContent)")
    }

    /// Saves lockfile resolved depedencies in `Tuist/Depedencies` directory.
    private func saveDepedencies(pathsProvider: CarthagePathsProvider) throws {
        // validation
        guard FileHandler.shared.exists(pathsProvider.temporaryCarfileResolvedPath) else {
            throw CarthageInteractorError.cartfileResolvedNotFound
        }
        guard FileHandler.shared.exists(pathsProvider.temporaryCarthageBuildDirectory) else {
            throw CarthageInteractorError.buildDirectoryNotFound
        }

        // save `Cartfile.resolved`
        try copy(
            from: pathsProvider.temporaryCarfileResolvedPath,
            to: pathsProvider.destinationCarfileResolvedPath
        )

        // save build directory
        try copy(
            from: pathsProvider.temporaryCarthageBuildDirectory,
            to: pathsProvider.destinationCarthageDirectory
        )
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
    let temporaryDirectoryPath: AbsolutePath

    let destinationCarfileResolvedPath: AbsolutePath
    let destinationCarthageDirectory: AbsolutePath

    let temporaryCarfileResolvedPath: AbsolutePath
    let temporaryCarthageBuildDirectory: AbsolutePath

    init(dependenciesDirectory: AbsolutePath, temporaryDirectoryPath: AbsolutePath) {
        self.dependenciesDirectory = dependenciesDirectory
        self.temporaryDirectoryPath = temporaryDirectoryPath

        destinationCarfileResolvedPath = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.lockfilesDirectoryName)
            .appending(component: Constants.DependenciesDirectory.cartfileResolvedName)
        destinationCarthageDirectory = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.carthageDirectoryName)

        temporaryCarfileResolvedPath = temporaryDirectoryPath
            .appending(component: Constants.DependenciesDirectory.cartfileResolvedName)
        temporaryCarthageBuildDirectory = temporaryDirectoryPath
            .appending(component: Constants.DependenciesDirectory.carthageDirectoryName)
            .appending(component: "Build")
    }
}
