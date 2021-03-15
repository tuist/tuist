import TSCBasic
import TuistGraph
import TuistSupport

enum SwiftPackageManagerInteractorError: FatalError, Equatable {
    /// Thrown when `Package.resolved` cannont be found in temporary directory after `Swift Package Manager` installation.
    case packageResolvedNotFound
    /// Thrown when `.build` directory cannont be found in temporary directory after `Swift Package Manager` installation.
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
    /// - Parameter dependenciesDirectory: The path to the directory that contains the `Tuist/Dependencies/` directory.
    /// - Parameter dependencies: List of dependencies to intall using `Swift Package Manager`.
    func fetch(dependenciesDirectory: AbsolutePath, dependencies: SwiftPackageManagerDependencies) throws
}

// MARK: - Swift Package Manager Interactor

public final class SwiftPackageManagerInteractor: SwiftPackageManagerInteracting {
    private let fileHandler: FileHandling

    public init(
        fileHandler: FileHandling = FileHandler.shared
    ) {
        self.fileHandler = fileHandler
    }

    public func fetch(dependenciesDirectory: AbsolutePath, dependencies: SwiftPackageManagerDependencies) throws {
        logger.info("Resolving and fetching Swift Package Manager dependencies.", metadata: .section)

        try fileHandler.inTemporaryDirectory { temporaryDirectoryPath in
            // prepare paths
            let pathsProvider = SwiftPackageManagerPathsProvider(
                dependenciesDirectory: dependenciesDirectory,
                temporaryDirectoryPath: temporaryDirectoryPath
            )

            // prepare for installation
            try prepareForInstallation(pathsProvider: pathsProvider, dependencies: dependencies)

            // build command
            let command = ["swift", "package", "--package-path", "\(temporaryDirectoryPath.pathString)", "resolve"]

            // run `Swift Package Manager`
            try System.shared.runAndPrint(command)

            // post installation
            try postInstallationActions(pathsProvider: pathsProvider)
        }

        logger.info("Packages resolved and fetched successfully.", metadata: .subsection)
    }

    // MARK: - Installation

    private func prepareForInstallation(pathsProvider: SwiftPackageManagerPathsProvider, dependencies: SwiftPackageManagerDependencies) throws {
        // copy `.build` directory from previous run if exist
        if fileHandler.exists(pathsProvider.destinationSwiftPackageManagerBuildDirectory) {
            try copyDirectory(
                from: pathsProvider.destinationSwiftPackageManagerBuildDirectory,
                to: pathsProvider.temporarySwiftPackageManagerBuildDirectory
            )
        }

        // copy `Package.resolved` directory from previous run if exist
        if fileHandler.exists(pathsProvider.destinationPackageResolvedPath) {
            try copyDirectory(
                from: pathsProvider.destinationPackageResolvedPath,
                to: pathsProvider.temporaryPackageResolvedPath
            )
        }

        // create `Package.swift`
        let packageManifestContent = dependencies.manifestValue()
        let packageManifestPath = pathsProvider.temporaryDirectoryPath.appending(component: "Package.swift")
        try fileHandler.write(packageManifestContent, path: packageManifestPath, atomically: true)

        // log
        logger.debug("Package.swift:", metadata: .subsection)
        logger.debug("\(packageManifestContent)")
    }

    private func postInstallationActions(pathsProvider: SwiftPackageManagerPathsProvider) throws {
        // validation
        guard fileHandler.exists(pathsProvider.temporaryPackageResolvedPath) else {
            throw SwiftPackageManagerInteractorError.packageResolvedNotFound
        }
        guard fileHandler.exists(pathsProvider.temporarySwiftPackageManagerBuildDirectory) else {
            throw SwiftPackageManagerInteractorError.buildDirectoryNotFound
        }

        // save `Package.resolved`
        try copyFile(
            from: pathsProvider.temporaryPackageResolvedPath,
            to: pathsProvider.destinationPackageResolvedPath
        )

        // save `.build` direcotry
        try copyDirectory(
            from: pathsProvider.temporarySwiftPackageManagerBuildDirectory,
            to: pathsProvider.destinationSwiftPackageManagerBuildDirectory
        )
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
}

// MARK: - Models

private struct SwiftPackageManagerPathsProvider {
    let dependenciesDirectory: AbsolutePath
    let temporaryDirectoryPath: AbsolutePath

    let destinationPackageResolvedPath: AbsolutePath
    let destinationSwiftPackageManagerBuildDirectory: AbsolutePath

    let temporaryPackageResolvedPath: AbsolutePath
    let temporarySwiftPackageManagerBuildDirectory: AbsolutePath

    init(dependenciesDirectory: AbsolutePath, temporaryDirectoryPath: AbsolutePath) {
        self.dependenciesDirectory = dependenciesDirectory
        self.temporaryDirectoryPath = temporaryDirectoryPath

        destinationPackageResolvedPath = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.lockfilesDirectoryName)
            .appending(component: Constants.DependenciesDirectory.packageResolvedName)
        destinationSwiftPackageManagerBuildDirectory = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.swiftPackageManagerDirectoryName)
            .appending(component: ".build")

        temporaryPackageResolvedPath = temporaryDirectoryPath
            .appending(component: Constants.DependenciesDirectory.packageResolvedName)
        temporarySwiftPackageManagerBuildDirectory = temporaryDirectoryPath
            .appending(component: ".build")
    }
}
