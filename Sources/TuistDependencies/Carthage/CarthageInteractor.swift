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
            return "Cartfile was not found after Cartage installation."
        case .buildDirectoryNotFound:
            return "Carthage/Build directory was not found after Cartage installation."
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

    public init(
        fileHandler: FileHandling = FileHandler.shared,
        carthageCommandGenerator: CarthageCommandGenerating = CarthageCommandGenerator(),
        cartfileContentGenerator: CartfileContentGenerating = CartfileContentGenerator(),
        carthageFrameworksInteractor: CarthageFrameworksInteracting = CarthageFrameworksInteractor()
    ) {
        self.fileHandler = fileHandler
        self.carthageCommandGenerator = carthageCommandGenerator
        self.cartfileContentGenerator = cartfileContentGenerator
        self.carthageFrameworksInteractor = carthageFrameworksInteractor
    }

    public func install(dependenciesDirectory: AbsolutePath, method: InstallDependenciesMethod, dependencies: [CarthageDependency]) throws {
        // check availability of `carthage`
        guard canUseSystemCarthage() else {
            throw CarthageInteractorError.carthageNotFound
        }

        // determine platforms
        let platforms: Set<Platform> = dependencies
            .reduce(Set<Platform>()) { platforms, dependency in platforms.union(dependency.platforms) }
        
        // prepare destination paths
        let destinationCarfileResolvedPath = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.lockfilesDirectoryName)
            .appending(component: Constants.DependenciesDirectory.cartfileResolvedName)
        let destinationCarthageDirectory = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.carthageDirectoryName)
        let destinationCarthageBuildDirectory = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.carthageDirectoryName)
            .appending(component: "Build")

        try fileHandler.inTemporaryDirectory { temporaryDirectoryPath in
            // prepare temporary paths
            let temporaryCarfileResolvedPath = temporaryDirectoryPath
                .appending(component: Constants.DependenciesDirectory.cartfileResolvedName)
            let temporaryCarthageBuildDirectory = temporaryDirectoryPath
                .appending(component: Constants.DependenciesDirectory.carthageDirectoryName)
                .appending(component: "Build")
            
            // copy build directory from previous run if exist
            if fileHandler.exists(destinationCarthageBuildDirectory) {
                try copyDirectory(from: destinationCarthageBuildDirectory, to: temporaryCarthageBuildDirectory)
            }
            
            // copy `Cartfile.resolved` from previous run if exist
            if fileHandler.exists(destinationCarfileResolvedPath) {
                try copyFile(from: destinationCarfileResolvedPath, to: temporaryCarfileResolvedPath)
            }
            
            // create `Cartfile`
            let cartfileContent = try cartfileContentGenerator.cartfileContent(for: dependencies)
            let cartfilePath = temporaryDirectoryPath.appending(component: "Cartfile")
            try fileHandler.write(cartfileContent, path: cartfilePath, atomically: true)
            
            // create `carthage` shell command
            let command = carthageCommandGenerator.command(method: method, path: temporaryDirectoryPath, platforms: platforms)

            // run `carthage`
            try System.shared.runAndPrint(command)

            // save `Cartfile.resolved`
            if fileHandler.exists(temporaryCarfileResolvedPath) {
                try copyFile(from: temporaryCarfileResolvedPath, to: destinationCarfileResolvedPath)
            } else {
                throw CarthageInteractorError.cartfileNotFound
            }

            if fileHandler.exists(temporaryCarthageBuildDirectory) {
                // save installed frameworks
                try carthageFrameworksInteractor.copyFrameworks(carthageBuildDirectory: temporaryCarthageBuildDirectory, destinationDirectory: destinationCarthageDirectory)
                
                // save build directory
                try copyDirectory(from: temporaryCarthageBuildDirectory, to: destinationCarthageBuildDirectory)
            } else {
                throw CarthageInteractorError.buildDirectoryNotFound
            }
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
