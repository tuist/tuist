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
            return .abort
        }
    }
    
    /// Error description.
    var description: String {
        switch self {
        case .packageResolvedNotFound:
            return "Package.resolved file was not found after Carthage installation."
        case .buildDirectoryNotFound:
            return ".build directory was not found after Carthage installation."
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
        logger.info("We are starting to fetch the Swift Package Manager dependencies.", metadata: .section)

        try fileHandler.inTemporaryDirectory { temporaryDirectoryPath in
            // prepare paths
            let pathsProvider = SwiftPackageManagerPathsProvider(
                dependenciesDirectory: dependenciesDirectory,
                temporaryDirectoryPath: temporaryDirectoryPath
            )
            
            // prepare for installation
            try prepareForInstallation(pathsProvider: pathsProvider, dependencies: dependencies)
            
            // build command
            let command = buildCommand(packagePath: temporaryDirectoryPath)
            
            // run `Swift Package Manager`
            logger.info("SwiftPackageManager:", metadata: .subsection)
            try System.shared.runAndPrint(command)
            
            // post installation
            try postInstallationActions(pathsProvider: pathsProvider)
        }
        
        logger.info("Swift Package Manage dependencies were fetched successfully.", metadata: .subsection)
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
        let packageManifestContent = dependencies.stringValue()
        let packageManifestPath = pathsProvider.temporaryDirectoryPath.appending(component: "Package.swift")
        try fileHandler.write(packageManifestContent, path: packageManifestPath, atomically: true)
        
        // log
        logger.info("Package.swift:", metadata: .subsection)
        logger.info("\(packageManifestContent)")
    }
    
    private func buildCommand(packagePath: AbsolutePath) -> [String] {
        let command = ["swift", "package", "--package-path", "\(packagePath.pathString)", "resolve"]
        
        // log
        logger.info("Command:", metadata: .subsection)
        logger.info("\(command.joined(separator: " "))")
        
        return command
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
