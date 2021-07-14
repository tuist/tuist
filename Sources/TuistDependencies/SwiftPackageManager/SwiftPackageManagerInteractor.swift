import TSCBasic
import TuistGraph
import TuistSupport

// MARK: - Swift Package Manager Interactor Errors

enum SwiftPackageManagerInteractorError: FatalError, Equatable {
    /// Thrown when `Package.resolved` cannot be found in temporary directory after `Swift Package Manager` installation.
    case packageResolvedNotFound
    /// Thrown when `.build` directory cannot be found in temporary directory after `Swift Package Manager` installation.
    case buildDirectoryNotFound

    /// Error type.
    var type: ErrorType {
        switch self {
        case .packageResolvedNotFound,
             .buildDirectoryNotFound:
            return .bug
        }
    }

    /// Error description.
    var description: String {
        switch self {
        case .packageResolvedNotFound:
            return "The Package.resolved lockfile was not found after resolving the dependencies using the Swift Package Manager."
        case .buildDirectoryNotFound:
            return "The .build directory was not found after resolving the dependencies using the Swift Package Manager"
        }
    }
}

// MARK: - Swift Package Manager Interacting

public protocol SwiftPackageManagerInteracting {
    /// Installs `Swift Package Manager` dependencies.
    /// - Parameters:
    ///   - dependenciesDirectory: The path to the directory that contains the `Tuist/Dependencies/` directory.
    ///   - dependencies: List of dependencies to install using `Swift Package Manager`.
    ///   - shouldUpdate: Indicates whether dependencies should be updated or fetched based on the `Tuist/Lockfiles/Package.resolved` lockfile.
    ///   - swiftToolsVersion: The version of Swift tools that will be used to resolve dependencies. If `nil` is passed then the environment’s version will be used.
    func install(
        dependenciesDirectory: AbsolutePath,
        dependencies: SwiftPackageManagerDependencies,
        shouldUpdate: Bool,
        swiftToolsVersion: String?
    ) throws

    /// Removes all cached `Swift Package Manager` dependencies.
    /// - Parameter dependenciesDirectory: The path to the directory that contains the `Tuist/Dependencies/` directory.
    func clean(dependenciesDirectory: AbsolutePath) throws
}

// MARK: - Swift Package Manager Interactor

public final class SwiftPackageManagerInteractor: SwiftPackageManagerInteracting {
    private let fileHandler: FileHandling
    private let swiftPackageManagerController: SwiftPackageManagerControlling

    public init(
        fileHandler: FileHandling = FileHandler.shared,
        swiftPackageManagerController: SwiftPackageManagerControlling = SwiftPackageManagerController()
    ) {
        self.fileHandler = fileHandler
        self.swiftPackageManagerController = swiftPackageManagerController
    }

    public func install(
        dependenciesDirectory: AbsolutePath,
        dependencies: SwiftPackageManagerDependencies,
        shouldUpdate: Bool,
        swiftToolsVersion: String?
    ) throws {
        logger.warning("Support for Swift Package Manager dependencies is currently being worked on and is not ready to be used yet.")
        logger.info("Installing Swift Package Manager dependencies.", metadata: .subsection)

        try fileHandler.inTemporaryDirectory { temporaryDirectoryPath in
            // prepare paths
            let pathsProvider = SwiftPackageManagerPathsProvider(
                dependenciesDirectory: dependenciesDirectory,
                temporaryDirectoryPath: temporaryDirectoryPath
            )

            // prepare for installation
            try loadDependencies(pathsProvider: pathsProvider, dependencies: dependencies, swiftToolsVersion: swiftToolsVersion)

            // run `Swift Package Manager`
            if shouldUpdate {
                try swiftPackageManagerController.update(at: temporaryDirectoryPath, printOutput: true)
            } else {
                try swiftPackageManagerController.resolve(at: temporaryDirectoryPath, printOutput: true)
            }

            // post installation
            try saveDepedencies(pathsProvider: pathsProvider)
        }

        logger.info("Swift Package Manager dependencies installed successfully.", metadata: .subsection)
    }

    public func clean(dependenciesDirectory: AbsolutePath) throws {
        let swiftPackageManagerDirectory = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.swiftPackageManagerDirectoryName)
        let packageResolvedPath = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.lockfilesDirectoryName)
            .appending(component: Constants.DependenciesDirectory.packageResolvedName)

        try fileHandler.delete(swiftPackageManagerDirectory)
        try fileHandler.delete(packageResolvedPath)
    }

    // MARK: - Installation

    /// Loads lockfile and dependencies into working directory if they had been saved before.
    private func loadDependencies(
        pathsProvider: SwiftPackageManagerPathsProvider,
        dependencies: SwiftPackageManagerDependencies,
        swiftToolsVersion: String?
    ) throws {
        // copy `.build` directory from previous run if exist
        if fileHandler.exists(pathsProvider.destinationBuildDirectory) {
            try copy(
                from: pathsProvider.destinationBuildDirectory,
                to: pathsProvider.temporaryBuildDirectory
            )
        }

        // copy `Package.resolved` directory from previous run if exist
        if fileHandler.exists(pathsProvider.destinationPackageResolvedPath) {
            try copy(
                from: pathsProvider.destinationPackageResolvedPath,
                to: pathsProvider.temporaryPackageResolvedPath
            )
        }

        // create `Package.swift`
        let packageManifestPath = pathsProvider.temporaryDirectoryPath.appending(component: "Package.swift")
        try fileHandler.write(dependencies.manifestValue(), path: packageManifestPath, atomically: true)

        // set `swift-tools-version` in `Package.swift`
        try swiftPackageManagerController.setToolsVersion(at: pathsProvider.temporaryDirectoryPath, to: swiftToolsVersion)

        // log
        let generatedManifestContent = try fileHandler.readTextFile(packageManifestPath)
        logger.debug("Package.swift:", metadata: .subsection)
        logger.debug("\(generatedManifestContent)")
    }

    /// Saves lockfile resolved depedencies in `Tuist/Depedencies` directory.
    private func saveDepedencies(pathsProvider: SwiftPackageManagerPathsProvider) throws {
        // validation
        guard fileHandler.exists(pathsProvider.temporaryPackageResolvedPath) else {
            throw SwiftPackageManagerInteractorError.packageResolvedNotFound
        }
        guard fileHandler.exists(pathsProvider.temporaryBuildDirectory) else {
            throw SwiftPackageManagerInteractorError.buildDirectoryNotFound
        }

        // save `Package.resolved`
        try copy(
            from: pathsProvider.temporaryPackageResolvedPath,
            to: pathsProvider.destinationPackageResolvedPath
        )

        // save `.build` directory
        try copy(
            from: pathsProvider.temporaryBuildDirectory,
            to: pathsProvider.destinationBuildDirectory
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

private struct SwiftPackageManagerPathsProvider {
    let dependenciesDirectory: AbsolutePath
    let temporaryDirectoryPath: AbsolutePath

    let destinationPackageResolvedPath: AbsolutePath
    let destinationBuildDirectory: AbsolutePath

    let temporaryPackageResolvedPath: AbsolutePath
    let temporaryBuildDirectory: AbsolutePath

    init(dependenciesDirectory: AbsolutePath, temporaryDirectoryPath: AbsolutePath) {
        self.dependenciesDirectory = dependenciesDirectory
        self.temporaryDirectoryPath = temporaryDirectoryPath

        destinationPackageResolvedPath = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.lockfilesDirectoryName)
            .appending(component: Constants.DependenciesDirectory.packageResolvedName)
        destinationBuildDirectory = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.swiftPackageManagerDirectoryName)

        temporaryPackageResolvedPath = temporaryDirectoryPath
            .appending(component: Constants.DependenciesDirectory.packageResolvedName)
        temporaryBuildDirectory = temporaryDirectoryPath
            .appending(component: ".build")
    }
}
