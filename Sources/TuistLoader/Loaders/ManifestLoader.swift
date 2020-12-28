import Foundation
import ProjectDescription
import RxBlocking
import RxSwift
import TSCBasic
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
    /// - Parameters:
    ///     - path: Path to the directory that contains the name_of_template.swift
    func loadTemplate(at path: AbsolutePath) throws -> ProjectDescription.Template

    /// Loads the Dependencies.swift in the given directory
    /// - Parameter path: Path to the directory that containst Dependencies.swift
    func loadDependencies(at path: AbsolutePath) throws -> ProjectDescription.Dependencies

    /// List all the manifests in the given directory.
    /// - Parameter path: Path to the directory whose manifest files will be returend.
    func manifests(at path: AbsolutePath) -> Set<Manifest>
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

        let setup = try loadManifestData(at: setupPath)
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

        let dependenciesData = try loadManifestData(at: dependencyPath)
        let decoder = JSONDecoder()
        return try decoder.decode(Dependencies.self, from: dependenciesData)
    }

    // MARK: - Private

    private func loadManifest<T: Decodable>(_ manifest: Manifest, at path: AbsolutePath) throws -> T {
        var fileNames = [manifest.fileName(path)]
        if let deprecatedFileName = manifest.deprecatedFileName {
            fileNames.insert(deprecatedFileName, at: 0)
        }

        for fileName in fileNames {
            let manifestPath = path.appending(component: fileName)
            if !FileHandler.shared.exists(manifestPath) { continue }
            let data = try loadManifestData(at: manifestPath)
            if Environment.shared.isVerbose {
                let string = String(data: data, encoding: .utf8)
                logger.debug("Trying to load the manifest represented by the following JSON representation:\n\(string ?? "")")
            }
            return try decoder.decode(T.self, from: data)
        }

        throw ManifestLoaderError.manifestNotFound(manifest, path)
    }

    private func loadManifestData(at path: AbsolutePath) throws -> Data {
        let projectDescriptionPath = try resourceLocator.projectDescription()
        let searchPaths = ProjectDescriptionSearchPaths.paths(for: projectDescriptionPath)
        var arguments: [String] = [
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

        // Helpers
        let projectDescriptionHelpersModulePath = try projectDescriptionHelpersBuilder.build(at: path, projectDescriptionSearchPaths: searchPaths)
        if let projectDescriptionHelpersModulePath = projectDescriptionHelpersModulePath {
            arguments.append(contentsOf: [
                "-I", projectDescriptionHelpersModulePath.parentDirectory.pathString,
                "-L", projectDescriptionHelpersModulePath.parentDirectory.pathString,
                "-F", projectDescriptionHelpersModulePath.parentDirectory.pathString,
                "-lProjectDescriptionHelpers",
            ])
        }

        arguments.append(path.pathString)
        arguments.append("--tuist-dump")

        let result = System.shared.observable(arguments,
                                              verbose: false,
                                              environment: environment.manifestLoadingVariables)
            .compactMap { (event) -> SystemEvent<Data>? in
                guard case let SystemEvent.standardOutput(data) = event, let string = String(data: data, encoding: .utf8) else { return nil }
                guard let startTokenRange = string.range(of: ManifestLoader.startManifestToken) else { return nil }
                guard let endTokenRange = string.range(of: ManifestLoader.endManifestToken) else { return nil }

                let preManifestLogs = String(string[string.startIndex ..< startTokenRange.lowerBound]).chomp()
                let postManifestLogs = String(string[endTokenRange.upperBound ..< string.endIndex]).chomp()

                if !preManifestLogs.isEmpty { logger.info("\(path.pathString): \(preManifestLogs)") }
                if !postManifestLogs.isEmpty { logger.info("\(path.pathString):\(postManifestLogs)") }

                let manifest = string[startTokenRange.upperBound ..< endTokenRange.lowerBound]
                return SystemEvent<Data>.standardOutput(manifest.data(using: .utf8)!)
            }
            .toBlocking()
            .materialize()

        switch result {
        case let .completed(elements):
            return elements.filter { $0.isStandardOutput }.map(\.value).reduce(into: Data()) { $0.append($1) }
        case let .failed(_, error):
            throw error
        }
    }
}
