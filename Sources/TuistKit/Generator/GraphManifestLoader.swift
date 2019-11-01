import Basic
import Foundation
import ProjectDescription
import TuistSupport

enum GraphManifestLoaderError: FatalError, Equatable {
    case projectDescriptionNotFound(AbsolutePath)
    case unexpectedOutput(AbsolutePath)
    case manifestNotFound(Manifest?, AbsolutePath)

    static func manifestNotFound(_ path: AbsolutePath) -> GraphManifestLoaderError {
        return .manifestNotFound(nil, path)
    }

    var description: String {
        switch self {
        case let .projectDescriptionNotFound(path):
            return "Couldn't find ProjectDescription.framework at path \(path.pathString)"
        case let .unexpectedOutput(path):
            return "Unexpected output trying to parse the manifest at path \(path.pathString)"
        case let .manifestNotFound(manifest, path):
            return "\(manifest?.fileName ?? "Manifest") not found at path \(path.pathString)"
        }
    }

    var type: ErrorType {
        switch self {
        case .unexpectedOutput:
            return .bug
        case .projectDescriptionNotFound:
            return .bug
        case .manifestNotFound:
            return .abort
        }
    }

    // MARK: - Equatable

    static func == (lhs: GraphManifestLoaderError, rhs: GraphManifestLoaderError) -> Bool {
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

enum Manifest: CaseIterable {
    case project
    case workspace
    case tuistConfig
    case setup

    var fileName: String {
        switch self {
        case .project:
            return "Project.swift"
        case .workspace:
            return "Workspace.swift"
        case .tuistConfig:
            return "TuistConfig.swift"
        case .setup:
            return "Setup.swift"
        }
    }
}

protocol GraphManifestLoading {
    /// Loads the TuistConfig.swift in the given directory.
    ///
    /// - Parameter path: Path to the directory that contains the TuistConfig.swift file.
    /// - Returns: Loaded TuistConfig.swift file.
    /// - Throws: An error if the file has a syntax error.
    func loadTuistConfig(at path: AbsolutePath) throws -> ProjectDescription.TuistConfig

    func loadProject(at path: AbsolutePath) throws -> ProjectDescription.Project
    func loadWorkspace(at path: AbsolutePath) throws -> ProjectDescription.Workspace
    func loadSetup(at path: AbsolutePath) throws -> [Upping]
    func manifests(at path: AbsolutePath) -> Set<Manifest>
    func manifestPath(at path: AbsolutePath, manifest: Manifest) throws -> AbsolutePath
}

class GraphManifestLoader: GraphManifestLoading {
    // MARK: - Attributes

    /// Resource locator to look up Tuist-related resources.
    let resourceLocator: ResourceLocating

    /// Instance to compile and return a temporary module that contains the helper files.
    let helpersLoader: GraphManifestHelpersLoading

    /// A decoder instance for decoding the raw manifest data to their concrete types
    private let decoder: JSONDecoder

    // MARK: - Init

    /// Initializes the manifest loader with its attributes.
    ///
    /// - Parameters:
    ///   - resourceLocator: Resource locator to look up Tuist-related resources.
    ///   - helpersLoader: Instance to compile and return a temporary module that contains the helper files.
    init(resourceLocator: ResourceLocating = ResourceLocator(),
         helpersLoader: GraphManifestHelpersLoading = GraphManifestHelpersLoader()) {
        self.resourceLocator = resourceLocator
        self.helpersLoader = helpersLoader
        decoder = JSONDecoder()
    }

    func manifestPath(at path: AbsolutePath, manifest: Manifest) throws -> AbsolutePath {
        let filePath = path.appending(component: manifest.fileName)

        if FileHandler.shared.exists(filePath) {
            return filePath
        } else {
            throw GraphManifestLoaderError.manifestNotFound(manifest, path)
        }
    }

    func manifests(at path: AbsolutePath) -> Set<Manifest> {
        return .init(Manifest.allCases.filter {
            FileHandler.shared.exists(path.appending(component: $0.fileName))
        })
    }

    /// Loads the TuistConfig.swift in the given directory.
    ///
    /// - Parameter path: Path to the directory that contains the TuistConfig.swift file.
    /// - Returns: Loaded TuistConfig.swift file.
    /// - Throws: An error if the file has a syntax error.
    func loadTuistConfig(at path: AbsolutePath) throws -> ProjectDescription.TuistConfig {
        return try loadManifest(.tuistConfig, at: path)
    }

    func loadProject(at path: AbsolutePath) throws -> ProjectDescription.Project {
        return try loadManifest(.project, at: path)
    }

    func loadWorkspace(at path: AbsolutePath) throws -> ProjectDescription.Workspace {
        return try loadManifest(.workspace, at: path)
    }

    func loadSetup(at path: AbsolutePath) throws -> [Upping] {
        let setupPath = path.appending(component: Manifest.setup.fileName)
        guard FileHandler.shared.exists(setupPath) else {
            throw GraphManifestLoaderError.manifestNotFound(.setup, path)
        }

        let setup = try loadManifestData(at: setupPath)
        let setupJson = try JSON(data: setup)
        let actionsJson: [JSON] = try setupJson.get("actions")
        return try actionsJson.compactMap {
            try Up.with(dictionary: $0,
                        projectPath: path)
        }
    }

    // MARK: - Private

    private func loadManifest<T: Decodable>(_ manifest: Manifest, at path: AbsolutePath) throws -> T {
        let manifestPath = path.appending(component: manifest.fileName)
        guard FileHandler.shared.exists(manifestPath) else {
            throw GraphManifestLoaderError.manifestNotFound(manifest, path)
        }
        let data = try loadManifestData(at: manifestPath)
        return try decoder.decode(T.self, from: data)
    }

    private func loadManifestData(at path: AbsolutePath) throws -> Data {
        let projectDescriptionPath = try resourceLocator.projectDescription()

        var arguments: [String] = [
            "/usr/bin/xcrun",
            "swiftc",
            "--driver-mode=swift",
            "-suppress-warnings",
            "-I", projectDescriptionPath.parentDirectory.pathString,
            "-L", projectDescriptionPath.parentDirectory.pathString,
            "-F", projectDescriptionPath.parentDirectory.pathString,
            "-lProjectDescription",
        ]

        // Helpers
        let (helpersModulePath, cleanupHelpersModule) = try helpersLoader.compileHelpersModule(at: path, projectDescriptionPath: projectDescriptionPath)
        if let helpersModulePath = helpersModulePath {
            arguments.append(contentsOf: [
                "-I", helpersModulePath.parentDirectory.pathString,
                "-L", helpersModulePath.parentDirectory.pathString,
                "-F", helpersModulePath.parentDirectory.pathString,
                "-lProjectDescriptionHelpers",
            ])
        }

        arguments.append(path.pathString)
        arguments.append("--tuist-dump")

        let result = try System.shared.capture(arguments).spm_chuzzle()
        guard let jsonString = result, let data = jsonString.data(using: .utf8) else {
            throw GraphManifestLoaderError.unexpectedOutput(path)
        }

        try cleanupHelpersModule()

        return data
    }
}
