import ProjectDescription
import TSCBasic
import TSCUtility
import TuistCore
import TuistGraph
import TuistSupport

// MARK: - Swift Package Manager Interactor Errors

enum SwiftPackageManagerInteractorError: FatalError, Equatable {
    /// Thrown when `Package.swift` cannot be found in temporary directory after `Swift Package Manager` installation.
    case packageSwiftNotFound
    /// Thrown when `Package.resolved` cannot be found in temporary directory after `Swift Package Manager` installation.
    case packageResolvedNotFound
    /// Thrown when `.build` directory cannot be found in temporary directory after `Swift Package Manager` installation.
    case buildDirectoryNotFound

    /// Error type.
    var type: ErrorType {
        switch self {
        case .packageSwiftNotFound,
             .packageResolvedNotFound,
             .buildDirectoryNotFound:
            return .bug
        }
    }

    /// Error description.
    var description: String {
        switch self {
        case .packageSwiftNotFound:
            return "The Package.swift file was not found after resolving the dependencies using the Swift Package Manager."
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
    ///   - platforms: Set of supported platforms.
    ///   - shouldUpdate: Indicates whether dependencies should be updated or fetched based on the `Tuist/Lockfiles/Package.resolved` lockfile.
    ///   - swiftToolsVersion: The version of Swift tools that will be used to resolve dependencies. If `nil` is passed then the environment’s version will be used.
    func install(
        dependenciesDirectory: AbsolutePath,
        dependencies: TuistGraph.SwiftPackageManagerDependencies,
        platforms: Set<TuistGraph.Platform>,
        shouldUpdate: Bool,
        swiftToolsVersion: TSCUtility.Version?
    ) throws -> TuistCore.DependenciesGraph

    /// Removes all cached `Swift Package Manager` dependencies.
    /// - Parameter dependenciesDirectory: The path to the directory that contains the `Tuist/Dependencies/` directory.
    func clean(dependenciesDirectory: AbsolutePath) throws
}

// MARK: - Swift Package Manager Interactor

public final class SwiftPackageManagerInteractor: SwiftPackageManagerInteracting {
    private let fileHandler: FileHandling
    private let swiftPackageManagerController: SwiftPackageManagerControlling
    private let swiftPackageManagerGraphGenerator: SwiftPackageManagerGraphGenerating

    public init(
        fileHandler: FileHandling = FileHandler.shared,
        swiftPackageManagerController: SwiftPackageManagerControlling = SwiftPackageManagerController(),
        swiftPackageManagerGraphGenerator: SwiftPackageManagerGraphGenerating = SwiftPackageManagerGraphGenerator(
            swiftPackageManagerController: SwiftPackageManagerController()
        )
    ) {
        self.fileHandler = fileHandler
        self.swiftPackageManagerController = swiftPackageManagerController
        self.swiftPackageManagerGraphGenerator = swiftPackageManagerGraphGenerator
    }

    public func install(
        dependenciesDirectory: AbsolutePath,
        dependencies: TuistGraph.SwiftPackageManagerDependencies,
        platforms: Set<TuistGraph.Platform>,
        shouldUpdate: Bool,
        swiftToolsVersion: TSCUtility.Version?
    ) throws -> TuistCore.DependenciesGraph {
        logger.info("Installing Swift Package Manager dependencies.", metadata: .subsection)

        let pathsProvider = SwiftPackageManagerPathsProvider(dependenciesDirectory: dependenciesDirectory)

        try loadDependencies(pathsProvider: pathsProvider, dependencies: dependencies, swiftToolsVersion: swiftToolsVersion)

        if shouldUpdate {
            try swiftPackageManagerController.update(at: pathsProvider.destinationSwiftPackageManagerDirectory, printOutput: true)
        } else {
            try swiftPackageManagerController.resolve(
                at: pathsProvider.destinationSwiftPackageManagerDirectory,
                printOutput: true
            )
        }

        try saveDependencies(
            pathsProvider: pathsProvider,
            hasRemoteDependencies: dependencies.packages.contains(where: \.isRemote)
        )

        let dependenciesGraph = try swiftPackageManagerGraphGenerator.generate(
            at: pathsProvider.destinationBuildDirectory,
            productTypes: dependencies.productTypes,
            platforms: platforms,
            baseSettings: dependencies.baseSettings,
            targetSettings: dependencies.targetSettings,
            swiftToolsVersion: swiftToolsVersion
        )

        logger.info("Swift Package Manager dependencies installed successfully.", metadata: .subsection)

        return dependenciesGraph
    }

    public func clean(dependenciesDirectory: AbsolutePath) throws {
        let pathsProvider = SwiftPackageManagerPathsProvider(dependenciesDirectory: dependenciesDirectory)
        try fileHandler.delete(pathsProvider.destinationSwiftPackageManagerDirectory)
        try fileHandler.delete(pathsProvider.destinationPackageResolvedPath)
    }

    // MARK: - Installation

    /// Loads lockfile and dependencies into working directory if they had been saved before.
    private func loadDependencies(
        pathsProvider: SwiftPackageManagerPathsProvider,
        dependencies: TuistGraph.SwiftPackageManagerDependencies,
        swiftToolsVersion: TSCUtility.Version?
    ) throws {
        let version = try TSCUtility.Version(versionString: try System.shared.swiftVersion(), usesLenientParsing: true)
        let isLegacy = version < TSCUtility.Version(5, 6, 0)

        // copy `Package.resolved` directory from lockfiles folder
        if fileHandler.exists(pathsProvider.destinationPackageResolvedPath) {
            try copy(
                from: pathsProvider.destinationPackageResolvedPath,
                to: pathsProvider.temporaryPackageResolvedPath
            )
        }

        // create `Package.swift`
        let packageManifestPath = pathsProvider.destinationPackageSwiftPath
        try fileHandler.createFolder(packageManifestPath.removingLastComponent())
        try fileHandler.write(dependencies.manifestValue(isLegacy: isLegacy), path: packageManifestPath, atomically: true)

        // set `swift-tools-version` in `Package.swift`
        try swiftPackageManagerController.setToolsVersion(
            at: pathsProvider.destinationSwiftPackageManagerDirectory,
            to: swiftToolsVersion?.description
        )

        let generatedManifestContent = try fileHandler.readTextFile(packageManifestPath)
        logger.debug("Package.swift:", metadata: .subsection)
        logger.debug("\(generatedManifestContent)")
    }

    /// Saves lockfile resolved dependencies in `Tuist/Dependencies` directory.
    private func saveDependencies(pathsProvider: SwiftPackageManagerPathsProvider, hasRemoteDependencies: Bool) throws {
        guard !hasRemoteDependencies || fileHandler.exists(pathsProvider.temporaryPackageResolvedPath) else {
            throw SwiftPackageManagerInteractorError.packageResolvedNotFound
        }
        guard fileHandler.exists(pathsProvider.destinationPackageSwiftPath) else {
            throw SwiftPackageManagerInteractorError.packageSwiftNotFound
        }
        guard fileHandler.exists(pathsProvider.destinationBuildDirectory) else {
            throw SwiftPackageManagerInteractorError.buildDirectoryNotFound
        }

        if fileHandler.exists(pathsProvider.temporaryPackageResolvedPath) {
            try copy(
                from: pathsProvider.temporaryPackageResolvedPath,
                to: pathsProvider.destinationPackageResolvedPath
            )
        }

        // remove temporary files
        try? FileHandler.shared.delete(pathsProvider.temporaryPackageResolvedPath)
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
    let destinationSwiftPackageManagerDirectory: AbsolutePath
    let destinationPackageSwiftPath: AbsolutePath
    let destinationPackageResolvedPath: AbsolutePath
    let destinationBuildDirectory: AbsolutePath

    let temporaryPackageResolvedPath: AbsolutePath

    init(dependenciesDirectory: AbsolutePath) {
        destinationPackageSwiftPath = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.swiftPackageManagerDirectoryName)
            .appending(component: Constants.DependenciesDirectory.packageSwiftName)
        destinationPackageResolvedPath = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.lockfilesDirectoryName)
            .appending(component: Constants.DependenciesDirectory.packageResolvedName)
        destinationSwiftPackageManagerDirectory = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.swiftPackageManagerDirectoryName)
        destinationBuildDirectory = destinationSwiftPackageManagerDirectory.appending(component: ".build")

        temporaryPackageResolvedPath = destinationSwiftPackageManagerDirectory
            .appending(component: Constants.DependenciesDirectory.packageResolvedName)
    }
}
