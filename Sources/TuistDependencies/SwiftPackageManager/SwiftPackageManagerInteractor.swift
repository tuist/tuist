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
    /// Fetches `Swift Package Manager` dependencies.
    /// - Parameters:
    ///   - dependenciesDirectory: The path to the directory that contains the `Tuist/Dependencies/` directory.
    ///   - dependencies: List of dependencies to fetch using `Swift Package Manager`.
    func fetch(
        dependenciesDirectory: AbsolutePath,
        dependencies: SwiftPackageManagerDependencies
    ) throws
    
    /// Updates `Swift Package Manager` dependencies.
    /// - Parameters:
    ///   - dependenciesDirectory: The path to the directory that contains the `Tuist/Dependencies/` directory.
    ///   - dependencies: List of dependencies to update using `Swift Package Manager`.
    func update(
        dependenciesDirectory: AbsolutePath,
        dependencies: SwiftPackageManagerDependencies
    ) throws

    /// Removes all cached `Swift Package Manager` dependencies.
    /// - Parameter dependenciesDirectory: The path to the directory that contains the `Tuist/Dependencies/` directory.
    func clean(dependenciesDirectory: AbsolutePath) throws
}

// MARK: - Swift Package Manager Interactor

public final class SwiftPackageManagerInteractor: SwiftPackageManagerInteracting {
    private let fileHandler: FileHandling
    private let swiftPackageManager: SwiftPackageManaging

    public init(
        fileHandler: FileHandling = FileHandler.shared,
        swiftPackageManager: SwiftPackageManaging = SwiftPackageManager()
    ) {
        self.fileHandler = fileHandler
        self.swiftPackageManager = swiftPackageManager
    }

    public func fetch(
        dependenciesDirectory: AbsolutePath,
        dependencies: SwiftPackageManagerDependencies
    ) throws {
        logger.warning("Support for Swift Package Manager dependencies is currently being worked on and is not ready to be used yet.")

        logger.info("Resolving and fetching Swift Package Manager dependencies.", metadata: .section)

        try install(
            dependenciesDirectory: dependenciesDirectory,
            dependencies: dependencies,
            installationMethod: { path in
                try swiftPackageManager.resolve(at: path)
            }
        )

        logger.info("Packages resolved and fetched successfully.", metadata: .subsection)
    }
    
    public func update(
        dependenciesDirectory: AbsolutePath,
        dependencies: SwiftPackageManagerDependencies
    ) throws {
        logger.warning("Support for Swift Package Manager dependencies is currently being worked on and is not ready to be used yet.")
        
        logger.info("Updating Swift Package Manager dependencies.", metadata: .section)
        
        try install(
            dependenciesDirectory: dependenciesDirectory,
            dependencies: dependencies,
            installationMethod: { path in
                try swiftPackageManager.update(at: path)
            }
        )
        
        logger.info("Updating resolved and fetched successfully.", metadata: .subsection)
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
    
    /// Installs given `dependencies` at `dependenciesDirectory` using `installationMethod`.
    private func install(
        dependenciesDirectory: AbsolutePath,
        dependencies: SwiftPackageManagerDependencies,
        installationMethod: (AbsolutePath) throws -> Void
    ) throws {
        try fileHandler.inTemporaryDirectory { temporaryDirectoryPath in
            // prepare paths
            let pathsProvider = SwiftPackageManagerPathsProvider(
                dependenciesDirectory: dependenciesDirectory,
                temporaryDirectoryPath: temporaryDirectoryPath
            )

            // prepare for installation
            try loadDependencies(pathsProvider: pathsProvider, packageManifestContent: dependencies.manifestValue())

            // run `Swift Package Manager`
            try installationMethod(temporaryDirectoryPath)

            // post installation
            try saveDepedencies(pathsProvider: pathsProvider)
        }
    }

    /// Loads lockfile and dependencies into working directory if they had been saved before.
    private func loadDependencies(pathsProvider: SwiftPackageManagerPathsProvider, packageManifestContent: String) throws {
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
        try fileHandler.write(packageManifestContent, path: packageManifestPath, atomically: true)

        // log
        logger.debug("Package.swift:", metadata: .subsection)
        logger.debug("\(packageManifestContent)")
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
