import Foundation
import ProjectDescription
import RxBlocking
import RxSwift
import TSCBasic
import TuistCore
import TuistSupport

public enum ManifestLoaderError: FatalError, Equatable {
    case projectDescriptionNotFound(AbsolutePath)
    case unexpectedOutput(AbsolutePath)
    case manifestNotFound(Manifest?, AbsolutePath)
    case manifestCachingFailed(Manifest?, AbsolutePath)

    public static func manifestNotFound(_ path: AbsolutePath) -> ManifestLoaderError {
        .manifestNotFound(nil, path)
    }

    public var description: String {
        switch self {
        case let .projectDescriptionNotFound(path):
            return "Couldn't find ProjectDescription.framework at path \(path.pathString)"
        case let .unexpectedOutput(path):
            return "Unexpected output trying to parse the manifest at path \(path.pathString)"
        case let .manifestNotFound(manifest, path):
            return "\(manifest?.fileName(path) ?? "Manifest") not found at path \(path.pathString)"
        case let .manifestCachingFailed(manifest, path):
            return "Could not cache \(manifest?.fileName(path) ?? "Manifest") at path \(path.pathString)"
        }
    }

    public var type: ErrorType {
        switch self {
        case .unexpectedOutput:
            return .bug
        case .projectDescriptionNotFound:
            return .bug
        case .manifestNotFound:
            return .abort
        case .manifestCachingFailed:
            return .abort
        }
    }

    // MARK: - Equatable

    public static func == (lhs: ManifestLoaderError, rhs: ManifestLoaderError) -> Bool {
        switch (lhs, rhs) {
        case let (.projectDescriptionNotFound(lhsPath), .projectDescriptionNotFound(rhsPath)):
            return lhsPath == rhsPath
        case let (.unexpectedOutput(lhsPath), .unexpectedOutput(rhsPath)):
            return lhsPath == rhsPath
        case let (.manifestNotFound(lhsManifest, lhsPath), .manifestNotFound(rhsManifest, rhsPath)):
            return lhsManifest == rhsManifest && lhsPath == rhsPath
        default:
            return false
        }
    }
}

public protocol ManifestLoading {
    /// Loads the Config.swift in the given directory.
    ///
    /// - Parameter path: Path to the directory that contains the Config.swift file.
    /// - Returns: Loaded Config.swift file.
    /// - Throws: An error if the file has a syntax error.
    func loadConfig(at path: AbsolutePath) throws -> ProjectDescription.Config

    /// Loads the Project.swift in the given directory.
    /// - Parameters:
    ///   - path: Path to the directory that contains the Project.swift.
    ///   - plugins: The plugins to use to while loading the project.
    func loadProject(at path: AbsolutePath, plugins: Plugins) throws -> ProjectDescription.Project

    /// Loads the Workspace.swift in the given directory.
    /// - Parameters:
    ///   - path: Path to the directory that contains the Workspace.swift
    ///   - plugins: The plugins to use to while loading the workspace.
    func loadWorkspace(at path: AbsolutePath, plugins: Plugins) throws -> ProjectDescription.Workspace

    /// Loads the Setup.swift in the given directory.
    /// - Parameters:
    ///     -  path: Path to the directory that contains the Setup.swift.
    ///     - plugins: The plugins to use while loading the manifest.
    func loadSetup(at path: AbsolutePath, plugins: Plugins) throws -> [Upping]

    /// Loads the name_of_template.swift in the given directory.
    /// - Parameters:
    ///     - path: Path to the directory that contains the name_of_template.swift
    ///     - plugins: The plugins to use while loading the manifest.
    func loadTemplate(at path: AbsolutePath, plugins: Plugins) throws -> ProjectDescription.Template

    /// Loads the Dependencies.swift in the given directory
    /// - Parameters:
    ///     -  path: Path to the directory that contains Dependencies.swift
    ///     - plugins: The plugins to use while loading the manifest.
    func loadDependencies(at path: AbsolutePath, plugins: Plugins) throws -> ProjectDescription.Dependencies

    /// Loads the Plugin.swift in the given directory.
    /// - Parameter path: Path to the directory that contains Plugin.swift
    func loadPlugin(at path: AbsolutePath) throws -> ProjectDescription.Plugin

    /// List all the manifests in the given directory.
    /// - Parameter path: Path to the directory whose manifest files will be returend.
    func manifests(at path: AbsolutePath) -> Set<Manifest>
}

public class ManifestLoader: ManifestLoading {
    // MARK: - Attributes

    let resourceLocator: ResourceLocating
    let projectDescriptionHelpersBuilder: ProjectDescriptionHelpersBuilding
    let manifestFilesLocator: ManifestFilesLocating
    let environment: Environmenting
    private let decoder: JSONDecoder

    // MARK: - Init

    public convenience init() {
        self.init(resourceLocator: ResourceLocator(),
                  projectDescriptionHelpersBuilder: ProjectDescriptionHelpersBuilder(),
                  manifestFilesLocator: ManifestFilesLocator())
    }

    init(environment: Environmenting = Environment.shared,
         resourceLocator: ResourceLocating,
         projectDescriptionHelpersBuilder: ProjectDescriptionHelpersBuilding,
         manifestFilesLocator: ManifestFilesLocating)
    {
        self.environment = environment
        self.resourceLocator = resourceLocator
        self.projectDescriptionHelpersBuilder = projectDescriptionHelpersBuilder
        self.manifestFilesLocator = manifestFilesLocator
        decoder = JSONDecoder()
    }

    public func manifests(at path: AbsolutePath) -> Set<Manifest> {
        Set(manifestFilesLocator.locateProjectManifests(at: path).map(\.0))
    }

    public func loadConfig(at path: AbsolutePath) throws -> ProjectDescription.Config {
        try loadManifest(.config, at: path)
    }

    public func loadProject(at path: AbsolutePath, plugins: Plugins) throws -> ProjectDescription.Project {
        try loadManifest(.project, at: path, plugins: plugins)
    }

    public func loadWorkspace(at path: AbsolutePath, plugins: Plugins) throws -> ProjectDescription.Workspace {
        try loadManifest(.workspace, at: path, plugins: plugins)
    }

    public func loadTemplate(at path: AbsolutePath, plugins: Plugins) throws -> ProjectDescription.Template {
        try loadManifest(.template, at: path, plugins: plugins)
    }

    public func loadPlugin(at path: AbsolutePath) throws -> ProjectDescription.Plugin {
        try loadManifest(.plugin, at: path)
    }

    public func loadSetup(at path: AbsolutePath, plugins: Plugins) throws -> [Upping] {
        let setupPath = path.appending(component: Manifest.setup.fileName(path))
        guard FileHandler.shared.exists(setupPath) else {
            throw ManifestLoaderError.manifestNotFound(.setup, path)
        }

        let setup = try loadDataForManifest(.setup, at: setupPath, plugins: plugins)
        let setupJson = try JSON(data: setup)
        let actionsJson: [JSON] = try setupJson.get("actions")
        return try actionsJson.compactMap {
            try Up.with(dictionary: $0,
                        projectPath: path)
        }
    }

    public func loadDependencies(at path: AbsolutePath, plugins: Plugins) throws -> ProjectDescription.Dependencies {
        let dependencyPath = path.appending(component: Manifest.dependencies.fileName(path))
        guard FileHandler.shared.exists(dependencyPath) else {
            throw ManifestLoaderError.manifestNotFound(.dependencies, path)
        }

        let dependenciesData = try loadDataForManifest(.dependencies, at: dependencyPath, plugins: plugins)
        let decoder = JSONDecoder()

        return try decoder.decode(Dependencies.self, from: dependenciesData)
    }

    // MARK: - Private

    private func loadManifest<T: Decodable>(
        _ manifest: Manifest,
        at path: AbsolutePath,
        plugins: Plugins = .none
    ) throws -> T {
        var fileNames = [manifest.fileName(path)]
        if let deprecatedFileName = manifest.deprecatedFileName {
            fileNames.insert(deprecatedFileName, at: 0)
        }

        for fileName in fileNames {
            let manifestPath = path.appending(component: fileName)
            if !FileHandler.shared.exists(manifestPath) { continue }
            let data = try loadDataForManifest(manifest, at: manifestPath, plugins: plugins)
            if Environment.shared.isVerbose {
                let string = String(data: data, encoding: .utf8)
                logger.debug("Trying to load the manifest represented by the following JSON representation:\n\(string ?? "")")
            }
            return try decoder.decode(T.self, from: data)
        }

        throw ManifestLoaderError.manifestNotFound(manifest, path)
    }

    private func loadDataForManifest(
        _ manifest: Manifest,
        at path: AbsolutePath,
        plugins: Plugins = .none
    ) throws -> Data {
        var arguments = [String]()
        let projectDescriptionPath = try resourceLocator.projectDescription()
        let searchPaths = ProjectDescriptionSearchPaths.paths(for: projectDescriptionPath)

        arguments.append(contentsOf: [
            "/usr/bin/xcrun",
            "swiftc",
            "--driver-mode=swift",
            "-suppress-warnings",
            "-I", searchPaths.includeSearchPath.pathString,
            "-L", searchPaths.librarySearchPath.pathString,
            "-F", searchPaths.frameworkSearchPath.pathString,
            "-lProjectDescription",
            "-framework", "ProjectDescription",
        ])

        let canLoadProjectDescriptionHelpers = manifest != .config && manifest != .plugin
        if canLoadProjectDescriptionHelpers {
            let projectDescriptionHelperModules = try projectDescriptionHelpersBuilder.build(
                at: path,
                projectDescriptionSearchPaths: searchPaths,
                customProjectDescriptionHelpers: plugins.projectDescriptionHelpers
            )

            projectDescriptionHelperModules.forEach {
                arguments.append(contentsOf: [
                    "-I", $0.path.parentDirectory.pathString,
                    "-L", $0.path.parentDirectory.pathString,
                    "-F", $0.path.parentDirectory.pathString,
                    "-l\($0.name)",
                ])
            }
        }

        arguments.append(path.pathString)
        arguments.append("--tuist-dump")

        let result = System.shared
            .observable(arguments, verbose: false, environment: environment.manifestLoadingVariables)
            .toBlocking()
            .materialize()

        switch result {
        case let .completed(elements):
            return elements.filter { $0.isStandardOutput }.map(\.value).reduce(into: Data()) { $0.append($1) }
        case let .failed(_, error):
            handleUnexpectedImportError(in: path, error: error, manifest: manifest, plugins: plugins)
            throw error
        }
    }

    /// Logs a help message to the user if attempting to import modules that
    /// are disallowed from certain manifests.
    private func handleUnexpectedImportError(in path: AbsolutePath, error: Error, manifest: Manifest, plugins: Plugins) {
        guard case let TuistSupport.SystemError.terminated(command, _, standardError) = error,
            manifest == .config || manifest == .plugin,
            command == "swiftc",
            let errorMessage = String(data: standardError, encoding: .utf8) else { return }

        let defaultHelpersName = ProjectDescriptionHelpersBuilder.defaultHelpersName
        let helperModules = [defaultHelpersName] + plugins.projectDescriptionHelpers.map(\.name)
        let hasImportedUnexpectedModule = helperModules.reduce(false) { $0 || errorMessage.contains($1) }
        guard hasImportedUnexpectedModule else { return }

        logger.error("Can't import \(defaultHelpersName) or plugins in \(manifest.fileName(path))")
    }
}
