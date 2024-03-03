import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

public enum ManifestLoaderError: FatalError, Equatable {
    case projectDescriptionNotFound(AbsolutePath)
    case unexpectedOutput(AbsolutePath)
    case manifestNotFound(Manifest?, AbsolutePath)
    case manifestCachingFailed(Manifest?, AbsolutePath)
    case manifestLoadingFailed(path: AbsolutePath, data: Data, context: String)

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
        case let .manifestLoadingFailed(path, _, context):
            return """
            Unable to load manifest at \(path.pathString.bold())
            \(context)
            """
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
        case .manifestLoadingFailed:
            return .abort
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

    /// Loads the name_of_template.swift in the given directory.
    /// - Parameter path: Path to the directory that contains the name_of_template.swift
    func loadTemplate(at path: AbsolutePath) throws -> ProjectDescription.Template

    /// Loads the `PackageSettings` from `Package.swift` in the given directory
    /// -  path: Path to the directory that contains Package.swift
    func loadPackageSettings(at path: AbsolutePath) throws -> ProjectDescription.PackageSettings

    /// Loads `Package.swift`
    /// - path: Path to the directory that contains Package.swift
    func loadPackage(at path: AbsolutePath) throws -> PackageInfo

    /// Loads the Plugin.swift in the given directory.
    /// - Parameter path: Path to the directory that contains Plugin.swift
    func loadPlugin(at path: AbsolutePath) throws -> ProjectDescription.Plugin

    /// List all the manifests in the given directory.
    /// - Parameter path: Path to the directory whose manifest files will be returned.
    func manifests(at path: AbsolutePath) -> Set<Manifest>

    /// Verifies that there is a project or workspace manifest at the given path, or throws an error otherwise.
    func validateHasRootManifest(at path: AbsolutePath) throws

    /// Registers plugins that will be used within the manifest loading process.
    /// - Parameter plugins: The plugins to register.
    func register(plugins: Plugins) throws
}

// swiftlint:disable:next type_body_length
public class ManifestLoader: ManifestLoading {
    // MARK: - Static

    static let startManifestToken = "TUIST_MANIFEST_START"
    static let endManifestToken = "TUIST_MANIFEST_END"

    // MARK: - Attributes

    let resourceLocator: ResourceLocating
    let manifestFilesLocator: ManifestFilesLocating
    let environment: Environmenting
    private let decoder: JSONDecoder
    private var plugins: Plugins = .none
    private let cacheDirectoryProviderFactory: CacheDirectoriesProviderFactoring
    private let projectDescriptionHelpersBuilderFactory: ProjectDescriptionHelpersBuilderFactoring
    private let xcodeController: XcodeControlling
    private let swiftPackageManagerController: SwiftPackageManagerControlling

    // MARK: - Init

    public convenience init() {
        self.init(
            environment: Environment.shared,
            resourceLocator: ResourceLocator(),
            cacheDirectoryProviderFactory: CacheDirectoriesProviderFactory(),
            projectDescriptionHelpersBuilderFactory: ProjectDescriptionHelpersBuilderFactory(),
            manifestFilesLocator: ManifestFilesLocator(),
            xcodeController: XcodeController.shared,
            swiftPackageManagerController: SwiftPackageManagerController()
        )
    }

    init(
        environment: Environmenting,
        resourceLocator: ResourceLocating,
        cacheDirectoryProviderFactory: CacheDirectoriesProviderFactoring,
        projectDescriptionHelpersBuilderFactory: ProjectDescriptionHelpersBuilderFactoring,
        manifestFilesLocator: ManifestFilesLocating,
        xcodeController: XcodeControlling,
        swiftPackageManagerController: SwiftPackageManagerControlling
    ) {
        self.environment = environment
        self.resourceLocator = resourceLocator
        self.cacheDirectoryProviderFactory = cacheDirectoryProviderFactory
        self.projectDescriptionHelpersBuilderFactory = projectDescriptionHelpersBuilderFactory
        self.manifestFilesLocator = manifestFilesLocator
        self.xcodeController = xcodeController
        self.swiftPackageManagerController = swiftPackageManagerController
        decoder = JSONDecoder()
    }

    public func manifests(at path: AbsolutePath) -> Set<Manifest> {
        Set(manifestFilesLocator.locateManifests(at: path).map(\.0))
    }

    public func validateHasRootManifest(at path: AbsolutePath) throws {
        let manifests = manifests(at: path)
        let rootManifests: Set<Manifest> = [.workspace, .project, .package]
        guard !manifests.isDisjoint(with: rootManifests) else {
            throw ManifestLoaderError.manifestNotFound(path)
        }
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

    public func loadPackage(at path: AbsolutePath) throws -> PackageInfo {
        try swiftPackageManagerController.loadPackageInfo(
            at: path
        )
    }

    public func loadPackageSettings(at path: AbsolutePath) throws -> ProjectDescription.PackageSettings {
        do {
            return try loadManifest(.packageSettings, at: path)
        } catch let error as ManifestLoaderError {
            switch error {
            case let .manifestLoadingFailed(path: _, data: data, context: _):
                if data.count == 0 {
                    return PackageSettings()
                } else {
                    throw error
                }
            default:
                throw error
            }
        }
    }

    public func loadPlugin(at path: AbsolutePath) throws -> ProjectDescription.Plugin {
        try loadManifest(.plugin, at: path)
    }

    public func register(plugins: Plugins) throws {
        self.plugins = plugins
    }

    // MARK: - Private

    // swiftlint:disable:next function_body_length
    private func loadManifest<T: Decodable>(
        _ manifest: Manifest,
        at path: AbsolutePath
    ) throws -> T {
        let manifestPath = try manifestPath(
            manifest,
            at: path
        )

        let data = try loadDataForManifest(manifest, at: manifestPath)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            guard let error = error as? DecodingError else {
                throw ManifestLoaderError.manifestLoadingFailed(
                    path: manifestPath,
                    data: data,
                    context: error.localizedDescription
                )
            }

            let json = (String(data: data, encoding: .utf8) ?? "nil")

            switch error {
            case let .typeMismatch(type, context):
                throw ManifestLoaderError.manifestLoadingFailed(
                    path: manifestPath,
                    data: data,
                    context: """
                    The content of the manifest did not match the expected type of: \(String(describing: type).bold())
                    \(context.debugDescription)
                    """
                )
            case let .valueNotFound(value, _):
                throw ManifestLoaderError.manifestLoadingFailed(
                    path: manifestPath,
                    data: data,
                    context: """
                    Expected a non-optional value for property of type \(String(describing: value).bold()) but found a nil value.
                    \(json.bold())
                    """
                )
            case let .keyNotFound(codingKey, _):
                throw ManifestLoaderError.manifestLoadingFailed(
                    path: manifestPath,
                    data: data,
                    context: """
                    Did not find property with name \(codingKey.stringValue.bold()) in the JSON represented by:
                    \(json.bold())
                    """
                )
            case let .dataCorrupted(context):
                throw ManifestLoaderError.manifestLoadingFailed(
                    path: manifestPath,
                    data: data,
                    context: """
                    The encoded data for the manifest is corrupted.
                    \(context.debugDescription)
                    """
                )
            @unknown default:
                throw ManifestLoaderError.manifestLoadingFailed(
                    path: manifestPath,
                    data: data,
                    context: """
                    Unable to decode the manifest for an unknown reason.
                    \(error.localizedDescription)
                    """
                )
            }
        }
    }

    private func manifestPath(
        _ manifest: Manifest,
        at path: AbsolutePath
    ) throws -> AbsolutePath {
        let manifestPath = path.appending(component: manifest.fileName(path))

        guard FileHandler.shared.exists(manifestPath) else {
            throw ManifestLoaderError.manifestNotFound(manifest, path)
        }

        return manifestPath
    }

    private func loadDataForManifest(
        _ manifest: Manifest,
        at path: AbsolutePath
    ) throws -> Data {
        let arguments = try buildArguments(
            manifest,
            at: path
        ) + ["--tuist-dump"]

        do {
            let string = try System.shared.capture(arguments, verbose: false, environment: environment.manifestLoadingVariables)

            guard let startTokenRange = string.range(of: ManifestLoader.startManifestToken),
                  let endTokenRange = string.range(of: ManifestLoader.endManifestToken)
            else {
                return string.data(using: .utf8)!
            }

            let preManifestLogs = String(string[string.startIndex ..< startTokenRange.lowerBound]).chomp()
            let postManifestLogs = String(string[endTokenRange.upperBound ..< string.endIndex]).chomp()

            if !preManifestLogs.isEmpty { logger.notice("\(path.pathString): \(preManifestLogs)") }
            if !postManifestLogs.isEmpty { logger.notice("\(path.pathString):\(postManifestLogs)") }

            let manifest = string[startTokenRange.upperBound ..< endTokenRange.lowerBound]
            return manifest.data(using: .utf8)!
        } catch {
            logUnexpectedImportErrorIfNeeded(in: path, error: error, manifest: manifest)
            logPluginHelperBuildErrorIfNeeded(in: path, error: error, manifest: manifest)
            throw error
        }
    }

    // swiftlint:disable:next function_body_length
    private func buildArguments(
        _ manifest: Manifest,
        at path: AbsolutePath
    ) throws -> [String] {
        let projectDescriptionPath = try resourceLocator.projectDescription()
        let searchPaths = ProjectDescriptionSearchPaths.paths(for: projectDescriptionPath)
        let frameworkName: String
        switch manifest {
        case .config,
             .plugin,
             .project,
             .template,
             .workspace,
             .package,
             .packageSettings:
            frameworkName = "ProjectDescription"
        }
        var arguments = [
            "/usr/bin/xcrun",
            "swift",
            "-suppress-warnings",
            "-I", searchPaths.includeSearchPath.pathString,
            "-L", searchPaths.librarySearchPath.pathString,
            "-F", searchPaths.frameworkSearchPath.pathString,
            "-l\(frameworkName)",
            "-framework", frameworkName,
        ]
        let projectDescriptionHelpersCacheDirectory = try cacheDirectoryProviderFactory
            .cacheDirectories()
            .tuistCacheDirectory(for: .projectDescriptionHelpers)

        let projectDescriptionHelperArguments: [String] = try {
            switch manifest {
            case .config, .plugin, .package:
                return []
            case .project,
                 .template,
                 .workspace,
                 .packageSettings:
                return try projectDescriptionHelpersBuilderFactory.projectDescriptionHelpersBuilder(
                    cacheDirectory: projectDescriptionHelpersCacheDirectory
                )
                .build(
                    at: path,
                    projectDescriptionSearchPaths: searchPaths,
                    projectDescriptionHelperPlugins: plugins.projectDescriptionHelpers
                ).flatMap { [
                    "-I", $0.path.parentDirectory.pathString,
                    "-L", $0.path.parentDirectory.pathString,
                    "-F", $0.path.parentDirectory.pathString,
                    "-l\($0.name)",
                ] }
            }
        }()

        let packageDescriptionArguments: [String] = try {
            if case .packageSettings = manifest {
                guard let xcode = try xcodeController.selected() else { return [] }
                let packageVersion = try swiftPackageManagerController.getToolsVersion(
                    at: path.parentDirectory
                )
                let manifestPath =
                    "\(xcode.path.pathString)/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/pm/ManifestAPI"
                return [
                    "-I", manifestPath,
                    "-L", manifestPath,
                    "-F", manifestPath,
                    "-lPackageDescription",
                    "-package-description-version", packageVersion.description,
                    "-D", "TUIST",
                ]
            } else {
                return []
            }
        }()

        arguments.append(contentsOf: projectDescriptionHelperArguments)
        arguments.append(contentsOf: packageDescriptionArguments)
        arguments.append(path.pathString)

        return arguments
    }

    private func logUnexpectedImportErrorIfNeeded(in path: AbsolutePath, error: Error, manifest: Manifest) {
        guard case let TuistSupport.SystemError.terminated(command, _, standardError) = error,
              manifest == .config || manifest == .plugin,
              command == "swiftc",
              let errorMessage = String(data: standardError, encoding: .utf8) else { return }

        let defaultHelpersName = ProjectDescriptionHelpersBuilder.defaultHelpersName

        if errorMessage.contains(defaultHelpersName) {
            logger.error("Cannot import \(defaultHelpersName) in \(manifest.fileName(path))")
            logger.notice("Project description helpers that depend on plugins are not allowed in \(manifest.fileName(path))")
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
