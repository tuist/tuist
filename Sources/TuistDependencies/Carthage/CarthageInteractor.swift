import RxBlocking
import TSCBasic
import TuistCore
import TuistSupport

// MARK: - Carthage Interactor Errors

enum CarthageInteractorError: FatalError, Equatable {
    /// Thrown when Carthage cannot be found.
    case carthageNotFound
    /// Thrown when Carfile cannont be found in temporary directory after Carthage installation.
    case cartfileNotFound
    /// Thrown when `Carthage/Build` directory cannont be found in temporary directory after Carthage installation.
    case buildDirectoryNotFound

    /// Error type.
    var type: ErrorType {
        switch self {
        case .carthageNotFound, .cartfileNotFound, .buildDirectoryNotFound:
            return .abort
        }
    }

    /// Error description.
    var description: String {
        switch self {
        case .carthageNotFound:
            return "Carthage was not found in the environment. It's possible that the tool is not installed or hasn't been exposed to your environment."
        case .cartfileNotFound:
            return "Cartfile was not found after Carthage installation."
        case .buildDirectoryNotFound:
            return "Carthage/Build directory was not found after Carthage installation."
        }
    }
}

// MARK: - Carthage Interacting

public protocol CarthageInteracting {
    /// Fetches `Carthage` dependencies.
    /// - Parameter dependenciesDirectory: The path to the directory that contains the `Tuist/Dependencies/` directory.
    /// - Parameter method: Installation method.
    /// - Parameter dependencies: List of dependencies to intall using `Carthage`.
    func fetch(dependenciesDirectory: AbsolutePath, dependencies: [CarthageDependency]) throws
}

// MARK: - Carthage Interactor

public final class CarthageInteractor: CarthageInteracting {
    private let fileHandler: FileHandling
    private let carthageCommandGenerator: CarthageCommandGenerating
    private let cartfileContentGenerator: CartfileContentGenerating

    public init(
        fileHandler: FileHandling = FileHandler.shared,
        carthageCommandGenerator: CarthageCommandGenerating = CarthageCommandGenerator(),
        cartfileContentGenerator: CartfileContentGenerating = CartfileContentGenerator()
    ) {
        self.fileHandler = fileHandler
        self.carthageCommandGenerator = carthageCommandGenerator
        self.cartfileContentGenerator = cartfileContentGenerator
    }

    public func fetch(dependenciesDirectory: AbsolutePath, dependencies: [CarthageDependency]) throws {
        logger.info("We are starting to fetch the Carthage dependencies.", metadata: .section)

        // check availability of `carthage`
        guard canUseSystemCarthage() else {
            throw CarthageInteractorError.carthageNotFound
        }

        // determine platforms
        let platforms: Set<Platform> = dependencies
            .reduce(Set<Platform>()) { platforms, dependency in platforms.union(dependency.platforms) }

        try fileHandler.inTemporaryDirectory { temporaryDirectoryPath in
            // prepare paths
            let pathsProvider = CarthagePathsProvider(dependenciesDirectory: dependenciesDirectory, temporaryDirectoryPath: temporaryDirectoryPath)

            // prepare for installation
            try prepareForInstallation(pathsProvider: pathsProvider, dependencies: dependencies)

            // create `carthage` shell command
            let command = carthageCommandGenerator.command(path: temporaryDirectoryPath, platforms: platforms)

            // run `carthage`
            try System.shared.runAndPrint(command)

            // post intallation actions
            try postInstallationActions(pathsProvider: pathsProvider)
        }

        logger.info("Carthage dependencies were fetched successfully.", metadata: .success)
    }

    // MARK: - Installation

    private func prepareForInstallation(pathsProvider: CarthagePathsProvider, dependencies: [CarthageDependency]) throws {
        // copy build directory from previous run if exist
        if fileHandler.exists(pathsProvider.destinationCarthageDirectory) {
            try copyDirectory(from: pathsProvider.destinationCarthageDirectory, to: pathsProvider.temporaryCarthageBuildDirectory)
        }

        // create `Cartfile`
        let cartfileContent = cartfileContentGenerator.cartfileContent(for: dependencies)
        let cartfilePath = pathsProvider.temporaryDirectoryPath.appending(component: "Cartfile")
        try fileHandler.write(cartfileContent, path: cartfilePath, atomically: true)
    }

    private func postInstallationActions(pathsProvider: CarthagePathsProvider) throws {
        // validation
        guard fileHandler.exists(pathsProvider.temporaryCarfileResolvedPath) else {
            throw CarthageInteractorError.cartfileNotFound
        }
        guard fileHandler.exists(pathsProvider.temporaryCarthageBuildDirectory) else {
            throw CarthageInteractorError.buildDirectoryNotFound
        }

        // save `Cartfile.resolved`
        try copyFile(from: pathsProvider.temporaryCarfileResolvedPath, to: pathsProvider.destinationCarfileResolvedPath)
        // save build directory
        try copyDirectory(from: pathsProvider.temporaryCarthageBuildDirectory, to: pathsProvider.destinationCarthageDirectory)
    }

    // MARK: - Helpers

    private func copyFile(from fromPath: AbsolutePath, to toPath: AbsolutePath) throws {
        try fileHandler.createFolder(toPath.removingLastComponent())

        if fileHandler.exists(toPath) {
            try fileHandler.replace(toPath, with: fromPath)
        } else {
            try fileHandler.copy(from: fromPath, to: toPath)
        }
    }

    private func copyDirectory(from fromPath: AbsolutePath, to toPath: AbsolutePath) throws {
        try fileHandler.createFolder(toPath.removingLastComponent())

        if fileHandler.exists(toPath) {
            try fileHandler.delete(toPath)
        }

        try fileHandler.copy(from: fromPath, to: toPath)
    }

    /// Returns true if Carthage is avaiable in the environment.
    /// - Returns: True if Carthege is available globally in the system.
    private func canUseSystemCarthage() -> Bool {
        do {
            _ = try System.shared.which("carthage")
            return true
        } catch {
            return false
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
