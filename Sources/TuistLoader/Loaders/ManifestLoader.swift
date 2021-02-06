import Foundation
import ProjectDescription
import RxBlocking
import RxSwift
import TSCBasic
import TuistGraph
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
    /// - Parameter path: Path to the directory that contains the Project.swift.
    func loadProject(at path: AbsolutePath) throws -> ProjectDescription.Project

    /// Loads the Workspace.swift in the given directory.
    /// - Parameter path: Path to the directory that contains the Workspace.swift
    func loadWorkspace(at path: AbsolutePath) throws -> ProjectDescription.Workspace

    /// Loads the Setup.swift in the given directory.
    /// - Parameter path: Path to the directory that contains the Setup.swift.
    func loadSetup(at path: AbsolutePath) throws -> [Upping]

    /// Loads the name_of_template.swift in the given directory.
    /// - Parameter path: Path to the directory that contains the name_of_template.swift
    func loadTemplate(at path: AbsolutePath) throws -> ProjectDescription.Template

    /// Loads the Dependencies.swift in the given directory
    /// - Parameters:
    ///     -  path: Path to the directory that contains Dependencies.swift
    func loadDependencies(at path: AbsolutePath) throws -> ProjectDescription.Dependencies

    /// Loads the Plugin.swift in the given directory.
    /// - Parameter path: Path to the directory that contains Plugin.swift
    func loadPlugin(at path: AbsolutePath) throws -> ProjectDescription.Plugin

    /// List all the manifests in the given directory.
    /// - Parameter path: Path to the directory whose manifest files will be returend.
    func manifests(at path: AbsolutePath) -> Set<Manifest>

    /// Registers plugins that will be used within the manifest loading process.
    /// - Parameter plugins: The plugins to register.
    func register(plugins: Plugins)
}

public class ManifestLoader: ManifestLoading {
    // MARK: - Static

    static let startManifestToken = "TUIST_MANIFEST_START"
    static let endManifestToken = "TUIST_MANIFEST_END"

    // MARK: - Attributes

    let resourceLocator: ResourceLocating
    let projectDescriptionHelpersBuilder: ProjectDescriptionHelpersBuilding
    let manifestFilesLocator: ManifestFilesLocating
    let environment: Environmenting
    private let decoder: JSONDecoder
    private var plugins: Plugins = .none

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

    public func loadProject(at path: AbsolutePath) throws -> ProjectDescription.Project {
        try loadManifest(.project, at: path)
    }

    public func loadWorkspace(at path: AbsolutePath) throws -> ProjectDescription.Workspace {
        try loadManifest(.workspace, at: path)
    }

    public func loadTemplate(at path: AbsolutePath) throws -> ProjectDescription.Template {
        try loadManifest(.template, at: path)
    }

    public func loadSetup(at path: AbsolutePath) throws -> [Upping] {
        let setupPath = path.appending(component: Manifest.setup.fileName(path))
        guard FileHandler.shared.exists(setupPath) else {
            throw ManifestLoaderError.manifestNotFound(.setup, path)
        }

        let setup = try loadDataForManifest(.setup, at: setupPath)
        let setupJson = try JSON(data: setup)
        let actionsJson: [JSON] = try setupJson.get("actions")
        return try actionsJson.compactMap {
            try Up.with(dictionary: $0,
                        projectPath: path)
        }
    }

    public func loadDependencies(at path: AbsolutePath) throws -> ProjectDescription.Dependencies {
        let dependencyPath = path.appending(components: Constants.tuistDirectoryName, Manifest.dependencies.fileName(path))
        guard FileHandler.shared.exists(dependencyPath) else {
            throw ManifestLoaderError.manifestNotFound(.dependencies, path)
        }

        let dependenciesData = try loadDataForManifest(.dependencies, at: dependencyPath)
        let decoder = JSONDecoder()

        return try decoder.decode(Dependencies.self, from: dependenciesData)
    }

    public func loadPlugin(at path: AbsolutePath) throws -> ProjectDescription.Plugin {
        try loadManifest(.plugin, at: path)
    }

    public func register(plugins: Plugins) {
        self.plugins = plugins
    }

    // MARK: - Private

    private func loadManifest<T: Decodable>(
        _ manifest: Manifest,
        at path: AbsolutePath
    ) throws -> T {
        var fileNames = [manifest.fileName(path)]
        if let deprecatedFileName = manifest.deprecatedFileName {
            fileNames.insert(deprecatedFileName, at: 0)
        }

        for fileName in fileNames {
            let manifestPath = path.appending(component: fileName)
            if !FileHandler.shared.exists(manifestPath) { continue }
            let data = try loadDataForManifest(manifest, at: manifestPath)
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
        at path: AbsolutePath
    ) throws -> Data {
        let projectDescriptionPath = try resourceLocator.projectDescription()
        let searchPaths = ProjectDescriptionSearchPaths.paths(for: projectDescriptionPath)
        var arguments = [
            "/usr/bin/xcrun",
            "swiftc",
            "--driver-mode=swift",
            "-suppress-warnings",
            "-I", searchPaths.includeSearchPath.pathString,
            "-L", searchPaths.librarySearchPath.pathString,
            "-F", searchPaths.frameworkSearchPath.pathString,
            "-lProjectDescription",
            "-framework", "ProjectDescription",
        ]

        let projectDescriptionHelperArguments = try projectDescriptionHelpersBuilder.build(
            at: path,
            projectDescriptionSearchPaths: searchPaths,
            projectDescriptionHelperPlugins: plugins.projectDescriptionHelpers
        ).flatMap { [
            "-I", $0.path.parentDirectory.pathString,
            "-L", $0.path.parentDirectory.pathString,
            "-F", $0.path.parentDirectory.pathString,
            "-l\($0.name)",
        ] }

        arguments.append(contentsOf: projectDescriptionHelperArguments)
        arguments.append(path.pathString)
        arguments.append("--tuist-dump")

        let result = System.shared
            .observable(arguments, verbose: false, environment: environment.manifestLoadingVariables)
            .toBlocking()
            .materialize()

        switch result {
        case let .completed(elements):
            let output = elements.filter { $0.isStandardOutput }.map(\.value).reduce(into: Data()) { $0.append($1) }
            guard let string = String(data: output, encoding: .utf8) else { return output }

            guard let startTokenRange = string.range(of: ManifestLoader.startManifestToken) else { return output }
            guard let endTokenRange = string.range(of: ManifestLoader.endManifestToken) else { return output }

            let preManifestLogs = String(string[string.startIndex ..< startTokenRange.lowerBound]).chomp()
            let postManifestLogs = String(string[endTokenRange.upperBound ..< string.endIndex]).chomp()

            if !preManifestLogs.isEmpty { logger.info("\(path.pathString): \(preManifestLogs)") }
            if !postManifestLogs.isEmpty { logger.info("\(path.pathString):\(postManifestLogs)") }

            let manifest = string[startTokenRange.upperBound ..< endTokenRange.lowerBound]
            return manifest.data(using: .utf8)!
        case let .failed(_, error):
            logUnexpectedImportErrorIfNeeded(in: path, error: error, manifest: manifest)
            logPluginHelperBuildErrorIfNeeded(in: path, error: error, manifest: manifest)
            throw error
        }
    }

    private func logUnexpectedImportErrorIfNeeded(in path: AbsolutePath, error: Error, manifest: Manifest) {
        guard case let TuistSupport.SystemError.terminated(command, _, standardError) = error,
            manifest == .config || manifest == .plugin,
            command == "swiftc",
            let errorMessage = String(data: standardError, encoding: .utf8) else { return }

        let defaultHelpersName = ProjectDescriptionHelpersBuilder.defaultHelpersName

        if errorMessage.contains(defaultHelpersName) {
            logger.error("Cannot import \(defaultHelpersName) in \(manifest.fileName(path))")
            logger.info("Project description helpers that depend on plugins are not allowed in \(manifest.fileName(path))")
        } else if errorMessage.contains("import") {
            logger.error("Helper plugins are not allowed in \(manifest.fileName(path))")
        }
    }

    private func logPluginHelperBuildErrorIfNeeded(in _: AbsolutePath, error: Error, manifest _: Manifest) {
        guard case let TuistSupport.SystemError.terminated(command, _, standardError) = error,
            command == "swiftc",
            let errorMessage = String(data: standardError, encoding: .utf8) else { return }

        let pluginHelpers = plugins.projectDescriptionHelpers
        guard let pluginHelper = pluginHelpers.first(where: { errorMessage.contains($0.name) }) else { return }

        logger.error("Unable to build plugin \(pluginHelper.name) located at \(pluginHelper.path)")
    }
}
