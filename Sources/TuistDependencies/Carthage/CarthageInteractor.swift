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

    /// Error type.
    var type: ErrorType {
        switch self {
        case .carthageNotFound, .cartfileNotFound:
            return .abort
        }
    }

    /// Error description.
    var description: String {
        switch self {
        case .carthageNotFound:
            return "Carthage was not found in the environment. It's possible that the tool is not installed or hasn't been exposed to your environment."
        case .cartfileNotFound:
            return "Cartfile was not found after Cartage installation."
        }
    }
}

// MARK: - Carthage Interacting

public protocol CarthageInteracting {
    /// Installes `Carthage` dependencies.
    /// - Parameter dependenciesDirectory: The path to the directory that contains the `Tuist/Dependencies/` directory.
    /// - Parameter method: Installation method.
    /// - Parameter dependencies: List of dependencies to intall using `Carthage`.
    func install(dependenciesDirectory: AbsolutePath, method: InstallDependenciesMethod, dependencies: [CarthageDependency]) throws
}

// MARK: - Carthage Interactor

public final class CarthageInteractor: CarthageInteracting {
    private let fileHandler: FileHandling
    private let carthageCommandGenerator: CarthageCommandGenerating
    private let cartfileContentGenerator: CartfileContentGenerating
    private let carthageFrameworksInteractor: CarthageFrameworksInteracting
    private let carthageVersionFilesInteractor: CarthageVersionFilesInteracting

    public init(
        fileHandler: FileHandling = FileHandler.shared,
        carthageCommandGenerator: CarthageCommandGenerating = CarthageCommandGenerator(),
        cartfileContentGenerator: CartfileContentGenerating = CartfileContentGenerator(),
        carthageFrameworksInteractor: CarthageFrameworksInteracting = CarthageFrameworksInteractor(),
        carthageVersionFilesInteractor: CarthageVersionFilesInteracting = CarthageVersionFilesInteractor()
    ) {
        self.fileHandler = fileHandler
        self.carthageCommandGenerator = carthageCommandGenerator
        self.cartfileContentGenerator = cartfileContentGenerator
        self.carthageFrameworksInteractor = carthageFrameworksInteractor
        self.carthageVersionFilesInteractor = carthageVersionFilesInteractor
    }

    public func install(dependenciesDirectory: AbsolutePath, method: InstallDependenciesMethod, dependencies: [CarthageDependency]) throws {
        // check availability of `carthage`
        guard canUseSystemCarthage() else {
            throw CarthageInteractorError.carthageNotFound
        }

        // determine platforms
        let platforms: Set<Platform> = dependencies
            .reduce(Set<Platform>()) { platforms, dependency in platforms.union(dependency.platforms) }

        try fileHandler.inTemporaryDirectory { temporaryDirectoryPath in
            // prepare paths
            let destinationCarfileResolvedPath = dependenciesDirectory
                .appending(component: Constants.DependenciesDirectory.lockfilesDirectoryName)
                .appending(component: Constants.DependenciesDirectory.cartfileResolvedName)
            let temporaryCarfileResolvedPath = temporaryDirectoryPath
                .appending(component: Constants.DependenciesDirectory.cartfileResolvedName)
            let carthageBuildDirectory = temporaryDirectoryPath
                .appending(components: "Carthage", "Build")

            // create `carthage` shell command
            let command = carthageCommandGenerator.command(method: method, path: temporaryDirectoryPath, platforms: platforms)

            // create `Cartfile`
            let cartfileContent = try cartfileContentGenerator.cartfileContent(for: dependencies)
            let cartfilePath = temporaryDirectoryPath.appending(component: "Cartfile")
            try fileHandler.write(cartfileContent, path: cartfilePath, atomically: true)

            // copy `Cartfile.resolved` from previous run if exist
            if fileHandler.exists(destinationCarfileResolvedPath) {
                try copyFile(from: destinationCarfileResolvedPath, to: temporaryCarfileResolvedPath)
            }
            
            // copy `.*.version` files from previous run if exist
            try carthageVersionFilesInteractor.loadVersionFiles(carthageBuildDirectory: carthageBuildDirectory, dependenciesDirectory: dependenciesDirectory)

            // run `carthage`
            try System.shared.runAndPrint(command)

            // save `Cartfile.resolved`
            if fileHandler.exists(temporaryCarfileResolvedPath) {
                try copyFile(from: temporaryCarfileResolvedPath, to: destinationCarfileResolvedPath)
            } else {
                throw CarthageInteractorError.cartfileNotFound
            }

            // save installed frameworks
            try carthageFrameworksInteractor.copyFrameworks(carthageBuildDirectory: carthageBuildDirectory, dependenciesDirectory: dependenciesDirectory)
            
            // save `.version` files
            try carthageVersionFilesInteractor.saveVersionFiles(carthageBuildDirectory: carthageBuildDirectory, dependenciesDirectory: dependenciesDirectory)
        }
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
