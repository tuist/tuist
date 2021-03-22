import RxBlocking
import TSCBasic
import TSCUtility
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
    /// Thrown when version of Carthage installed in environment does not support XCFrameworks production.
    case xcFrameworksProductionNotSupported

    /// Error type.
    var type: ErrorType {
        switch self {
        case .cartfileResolvedNotFound,
             .buildDirectoryNotFound:
            return .bug
        case .carthageNotFound,
             .xcFrameworksProductionNotSupported:
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
        case .xcFrameworksProductionNotSupported:
            return """
            The version of Carthage installed in your environment doesn't suppport production of XCFrameworks.
            Update the tool or disbale XCFrameworks in your Dependencies.swift manifest.
            """
        }
    }
}

// MARK: - Carthage Interacting

public protocol CarthageInteracting {
    /// Fetches `Carthage` dependencies.
    /// - Parameter dependenciesDirectory: The path to the directory that contains the `Tuist/Dependencies/` directory.
    /// - Parameter dependencies: List of dependencies to intall using `Carthage`.
    func fetch(dependenciesDirectory: AbsolutePath, dependencies: CarthageDependencies) throws
    
    /// Removes all cached `Carthage` dependencies.
    /// - Parameter dependenciesDirectory: The path to the directory that contains the `Tuist/Dependencies/` directory.
    func clean(dependenciesDirectory: AbsolutePath) throws
}

// MARK: - Carthage Interactor

public final class CarthageInteractor: CarthageInteracting {
    private let fileHandler: FileHandling
    private let carthageController: CarthageControlling
    private let carthageCommandGenerator: CarthageCommandGenerating

    public init(
        fileHandler: FileHandling = FileHandler.shared,
        carthageController: CarthageControlling = CarthageController.shared,
        carthageCommandGenerator: CarthageCommandGenerating = CarthageCommandGenerator()
    ) {
        self.fileHandler = fileHandler
        self.carthageController = carthageController
        self.carthageCommandGenerator = carthageCommandGenerator
    }

    public func fetch(dependenciesDirectory: AbsolutePath, dependencies: CarthageDependencies) throws {
        logger.info("Resolving and fetching Carthage dependencies.", metadata: .section)

        // check availability of `carthage`
        guard carthageController.canUseSystemCarthage() else {
            throw CarthageInteractorError.carthageNotFound
        }

        // check if XCFrameworks production supported if it is needed
        if dependencies.options.contains(.useXCFrameworks), !(try carthageController.isXCFrameworksProductionSupported()) {
            throw CarthageInteractorError.xcFrameworksProductionNotSupported
        }

        try fileHandler.inTemporaryDirectory { temporaryDirectoryPath in
            // prepare paths
            let pathsProvider = CarthagePathsProvider(
                dependenciesDirectory: dependenciesDirectory,
                temporaryDirectoryPath: temporaryDirectoryPath
            )

            // prepare for installation
            try loadDependencies(pathsProvider: pathsProvider, dependencies: dependencies)

            // run `Carthage`
            let command = carthageCommandGenerator.command(
                path: temporaryDirectoryPath,
                platforms: dependencies.platforms,
                options: dependencies.options
            )
            try System.shared.runAndPrint(command)

            // post installation
            try saveDepedencies(pathsProvider: pathsProvider)
        }

        logger.info("Carthage dependencies resolved and fetched successfully.", metadata: .subsection)
    }
    
    public func clean(dependenciesDirectory: AbsolutePath) throws {
        let carthageDirectory = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.carthageDirectoryName)
        let cartfileResolvedPath = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.lockfilesDirectoryName)
            .appending(component: Constants.DependenciesDirectory.cartfileResolvedName)
        
        try fileHandler.delete(carthageDirectory)
        try fileHandler.delete(cartfileResolvedPath)
    }

    // MARK: - Installation

    /// Loads lockfile and dependencies into working directory if they had been saved before.
    private func loadDependencies(pathsProvider: CarthagePathsProvider, dependencies: CarthageDependencies) throws {
        // copy build directory from previous run if exist
        if fileHandler.exists(pathsProvider.destinationCarthageDirectory) {
            try copy(
                from: pathsProvider.destinationCarthageDirectory,
                to: pathsProvider.temporaryCarthageBuildDirectory
            )
        }

        // copy `Cartfile.resolved` directory from previous run if exist
        if fileHandler.exists(pathsProvider.destinationCarfileResolvedPath) {
            try copy(
                from: pathsProvider.destinationCarfileResolvedPath,
                to: pathsProvider.temporaryCarfileResolvedPath
            )
        }

        // create `Cartfile`
        let cartfileContent = dependencies.cartfileValue()
        let cartfilePath = pathsProvider.temporaryDirectoryPath.appending(component: "Cartfile")
        try fileHandler.write(cartfileContent, path: cartfilePath, atomically: true)

        // log
        logger.debug("Cartfile:", metadata: .subsection)
        logger.debug("\(cartfileContent)")
    }

    /// Saves lockfile resolved depedencies in `Tuist/Depedencies` directory.
    private func saveDepedencies(pathsProvider: CarthagePathsProvider) throws {
        // validation
        guard fileHandler.exists(pathsProvider.temporaryCarfileResolvedPath) else {
            throw CarthageInteractorError.cartfileResolvedNotFound
        }
        guard fileHandler.exists(pathsProvider.temporaryCarthageBuildDirectory) else {
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
        if fileHandler.exists(toPath) {
            try fileHandler.replace(toPath, with: fromPath)
        } else {
            try fileHandler.createFolder(toPath.removingLastComponent())
            try fileHandler.copy(from: fromPath, to: toPath)
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
