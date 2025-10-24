import FileSystem
import Foundation
import Mockable
import Path
import ProjectDescription
import TuistCore
import TuistSupport
import XcodeGraph

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

@Mockable
public protocol ManifestLoading {
    /// Loads the Tuist.swift in the given directory.
    ///
    /// - Parameter path: Path to the directory that contains the Tuist.swift file.
    /// - Returns: Loaded Tuist.swift file.
    /// - Throws: An error if the file has a syntax error.
    func loadConfig(at path: AbsolutePath) async throws -> ProjectDescription.Config

    /// Loads the Project.swift in the given directory.
    /// - Parameters:
    ///   - path: Path to the directory that contains the Project.swift.
    ///   - disableSandbox: Whether to disable loading the manifest in a sandboxed environment.
    func loadProject(at path: AbsolutePath, disableSandbox: Bool) async throws -> ProjectDescription.Project

    /// Loads the Workspace.swift in the given directory.
    /// - Parameters:
    ///   - path: Path to the directory that contains the Workspace.swift.
    ///   - disableSandbox: Whether to disable loading the manifest in a sandboxed environment.
    func loadWorkspace(at path: AbsolutePath, disableSandbox: Bool) async throws -> ProjectDescription.Workspace

    /// Loads the name_of_template.swift in the given directory.
    /// - Parameter path: Path to the directory that contains the name_of_template.swift
    func loadTemplate(at path: AbsolutePath) async throws -> ProjectDescription.Template

    /// Loads the `PackageSettings` from `Package.swift` in the given directory
    /// - Parameters:
    ///   - path: Path to the directory that contains Package.swift
    ///   - disableSandbox: Whether to disable loading the manifest in a sandboxed environment.
    func loadPackageSettings(at path: AbsolutePath, disableSandbox: Bool) async throws -> ProjectDescription.PackageSettings

    /// Loads `Package.swift`
    /// - Parameter path: Path to the directory that contains Package.swift
    func loadPackage(at path: AbsolutePath, disableSandbox: Bool) async throws -> PackageInfo

    /// Loads the Plugin.swift in the given directory.
    /// - Parameter path: Path to the directory that contains Plugin.swift
    func loadPlugin(at path: AbsolutePath) async throws -> ProjectDescription.Plugin

    /// List all the manifests in the given directory.
    /// - Parameter path: Path to the directory whose manifest files will be returned.
    func manifests(at path: AbsolutePath) async throws -> Set<Manifest>

    /// Verifies that there is a project or workspace manifest at the given path, or throws an error otherwise.
    func validateHasRootManifest(at path: AbsolutePath) async throws

    /// - Returns: `true` if there is a project or workspace manifest at the given path
    func hasRootManifest(at path: AbsolutePath) async throws -> Bool

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
    private let cacheDirectoriesProvider: CacheDirectoriesProviding
    private let projectDescriptionHelpersBuilderFactory: ProjectDescriptionHelpersBuilderFactoring
    private let swiftPackageManagerController: SwiftPackageManagerControlling
    private let packageInfoLoader: PackageInfoLoading
    private let fileSystem: FileSysteming

    // MARK: - Init

    public convenience init() {
        self.init(
            environment: Environment.current,
            resourceLocator: ResourceLocator(),
            cacheDirectoriesProvider: CacheDirectoriesProvider(),
            projectDescriptionHelpersBuilderFactory: ProjectDescriptionHelpersBuilderFactory(),
            manifestFilesLocator: ManifestFilesLocator(),
            swiftPackageManagerController: SwiftPackageManagerController(),
            packageInfoLoader: PackageInfoLoader()
        )
    }

    init(
        environment: Environmenting,
        resourceLocator: ResourceLocating,
        cacheDirectoriesProvider: CacheDirectoriesProviding,
        projectDescriptionHelpersBuilderFactory: ProjectDescriptionHelpersBuilderFactoring,
        manifestFilesLocator: ManifestFilesLocating,
        swiftPackageManagerController: SwiftPackageManagerControlling,
        packageInfoLoader: PackageInfoLoading,
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.environment = environment
        self.resourceLocator = resourceLocator
        self.cacheDirectoriesProvider = cacheDirectoriesProvider
        self.projectDescriptionHelpersBuilderFactory = projectDescriptionHelpersBuilderFactory
        self.manifestFilesLocator = manifestFilesLocator
        self.swiftPackageManagerController = swiftPackageManagerController
        self.packageInfoLoader = packageInfoLoader
        self.fileSystem = fileSystem
        decoder = JSONDecoder()
    }

    public func manifests(at path: AbsolutePath) async throws -> Set<Manifest> {
        try await Set(manifestFilesLocator.locateManifests(at: path).map(\.0))
    }

    public func validateHasRootManifest(at path: AbsolutePath) async throws {
        guard try await hasRootManifest(at: path) else {
            throw ManifestLoaderError.manifestNotFound(path)
        }
    }

    public func hasRootManifest(at path: AbsolutePath) async throws -> Bool {
        let manifests = try await manifests(at: path)
        let rootManifests: Set<Manifest> = [.workspace, .project, .package]
        return !manifests.isDisjoint(with: rootManifests)
    }

    public func loadConfig(at path: AbsolutePath) async throws -> ProjectDescription.Config {
        try await loadManifest(.config, at: path, disableSandbox: true)
    }

    public func loadProject(at path: AbsolutePath, disableSandbox: Bool) async throws -> ProjectDescription.Project {
        try await loadManifest(.project, at: path, disableSandbox: disableSandbox)
    }

    public func loadWorkspace(at path: AbsolutePath, disableSandbox: Bool) async throws -> ProjectDescription.Workspace {
        try await loadManifest(.workspace, at: path, disableSandbox: disableSandbox)
    }

    public func loadTemplate(at path: AbsolutePath) async throws -> ProjectDescription.Template {
        try await loadManifest(.template, at: path, disableSandbox: true)
    }

    public func loadPackage(at path: AbsolutePath, disableSandbox: Bool) async throws -> PackageInfo {
        try await packageInfoLoader.loadPackageInfo(at: path, disableSandbox: disableSandbox)
    }

    public func loadPackageSettings(at path: AbsolutePath, disableSandbox: Bool) async throws -> ProjectDescription
        .PackageSettings
    {
        do {
            return try await loadManifest(.packageSettings, at: path, disableSandbox: disableSandbox)
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

    public func loadPlugin(at path: AbsolutePath) async throws -> ProjectDescription.Plugin {
        try await loadManifest(.plugin, at: path, disableSandbox: true)
    }

    public func register(plugins: Plugins) throws {
        self.plugins = plugins
    }

    // MARK: - Private

    // swiftlint:disable:next function_body_length
    private func loadManifest<T: Decodable>(
        _ manifest: Manifest,
        at path: AbsolutePath,
        disableSandbox: Bool
    ) async throws -> T {
        let manifestPath = try await manifestPath(
            manifest,
            at: path
        )

        let data = try await loadDataForManifest(manifest, at: manifestPath, disableSandbox: disableSandbox)

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
    ) async throws -> AbsolutePath {
        let manifestPathCandidates = [
            path.appending(component: manifest.fileName(path)),
            manifest.alternativeFileName(path).map { path.appending(component: $0) },
        ].compactMap { $0 }
        for candidate in manifestPathCandidates {
            if try await fileSystem.exists(candidate) {
                return candidate
            }
        }
        throw ManifestLoaderError.manifestNotFound(manifest, path)
    }

    private func loadDataForManifest(
        _ manifest: Manifest,
        at path: AbsolutePath,
        disableSandbox: Bool
    ) async throws -> Data {
        let arguments = try await buildArguments(
            manifest,
            at: path,
            disableSandbox: disableSandbox
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

            if !preManifestLogs.isEmpty { Logger.current.notice("\(path.pathString): \(preManifestLogs)") }
            if !postManifestLogs.isEmpty { Logger.current.notice("\(path.pathString):\(postManifestLogs)") }

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
        at path: AbsolutePath,
        disableSandbox: Bool
    ) async throws -> [String] {
        let projectDescriptionPath = try await resourceLocator.projectDescription()
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
        let projectDescriptionHelpersCacheDirectory = try cacheDirectoriesProvider
            .cacheDirectory(for: .projectDescriptionHelpers)

        let projectDescriptionHelperModules: [ProjectDescriptionHelpersModule] = try await {
            switch manifest {
            case .config, .plugin, .package:
                return []
            case .project,
                 .template,
                 .workspace,
                 .packageSettings:
                return try await projectDescriptionHelpersBuilderFactory.projectDescriptionHelpersBuilder(
                    cacheDirectory: projectDescriptionHelpersCacheDirectory
                )
                .build(
                    at: path,
                    projectDescriptionSearchPaths: searchPaths,
                    projectDescriptionHelperPlugins: plugins.projectDescriptionHelpers
                )
            }
        }()
        let projectDescriptionHelperArguments = projectDescriptionHelperModules.flatMap { [
            "-I", $0.path.parentDirectory.pathString,
            "-L", $0.path.parentDirectory.pathString,
            "-F", $0.path.parentDirectory.pathString,
            "-l\($0.name)",
        ] }

        let packageDescriptionArguments: [String] = try await {
            if case .packageSettings = manifest {
                let xcode = try await XcodeController.current.selected()
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

        if !disableSandbox {
            #if os(macOS)
                let profile = macOSSandboxProfile(
                    readOnlyPaths: Set(
                        [
                            path,
                            try await XcodeController.current.selected().path,
                            AbsolutePath("/Library/Preferences/com.apple.dt.Xcode.plist"),
                            searchPaths.includeSearchPath,
                            searchPaths.librarySearchPath,
                            searchPaths.frameworkSearchPath,
                        ] + projectDescriptionHelperModules.map(\.path.parentDirectory)
                    )
                )
                return ["sandbox-exec", "-p", profile] + arguments
            #else
                return arguments
            #endif
        } else {
            return arguments
        }
    }

    private func macOSSandboxProfile(
        readOnlyPaths: Set<AbsolutePath>
    ) -> String {
        """
        (version 1)

        ; Deny all operations by default unless explicitly allowed
        (deny default)

        ; Import base system rules
        (import "system.sb")

        ; Allow process operations (fork, exec, etc.)
        (allow process*)
        ; Allow querying information about the current process
        (allow process-info* (target self))

        ; Allow reading file metadata (permissions, size, etc.)
        (allow file-read-metadata)

        ; Allow reading and writing temporary and intermediate build files and caches
        (allow file-read* file-write* (subpath "/private/tmp/"))
        (allow file-read* file-write* (subpath "/private/var/"))

        ; Allow reading from specified paths
        \(readOnlyPaths.map { "(allow file-read* (subpath \"\($0)\"))" }.joined(separator: "\n"))
        """
    }

    private func logUnexpectedImportErrorIfNeeded(in path: AbsolutePath, error: Error, manifest: Manifest) {
        guard case let TuistSupport.SystemError.terminated(command, _, standardError) = error,
              manifest == .config || manifest == .plugin,
              command == "swiftc",
              let errorMessage = String(data: standardError, encoding: .utf8) else { return }

        let defaultHelpersName = ProjectDescriptionHelpersBuilder.defaultHelpersName

        if errorMessage.contains(defaultHelpersName) {
            Logger.current.error("Cannot import \(defaultHelpersName) in \(manifest.fileName(path))")
            Logger.current
                .notice("Project description helpers that depend on plugins are not allowed in \(manifest.fileName(path))")
        } else if errorMessage.contains("import") {
            Logger.current.error("Helper plugins are not allowed in \(manifest.fileName(path))")
        }
    }

    private func logPluginHelperBuildErrorIfNeeded(in _: AbsolutePath, error: Error, manifest _: Manifest) {
        guard case let TuistSupport.SystemError.terminated(command, _, standardError) = error,
              command == "swiftc",
              let errorMessage = String(data: standardError, encoding: .utf8) else { return }

        let pluginHelpers = plugins.projectDescriptionHelpers
        guard let pluginHelper = pluginHelpers.first(where: { errorMessage.contains($0.name) }) else { return }

        Logger.current.error("Unable to build plugin \(pluginHelper.name) located at \(pluginHelper.path)")
    }
}
