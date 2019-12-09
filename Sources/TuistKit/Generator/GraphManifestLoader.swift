import Basic
import Foundation
import ProjectDescription
import TuistSupport

enum GraphManifestLoaderError: FatalError, Equatable {
    case projectDescriptionNotFound(AbsolutePath)
    case unexpectedOutput(AbsolutePath)
    case manifestNotFound(Manifest?, AbsolutePath)

    static func manifestNotFound(_ path: AbsolutePath) -> GraphManifestLoaderError {
        .manifestNotFound(nil, path)
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

protocol GraphManifestLoading {
    /// Loads the TuistConfig.swift in the given directory.
    ///
    /// - Parameter path: Path to the directory that contains the TuistConfig.swift file.
    /// - Returns: Loaded TuistConfig.swift file.
    /// - Throws: An error if the file has a syntax error.
    func loadTuistConfig(at path: AbsolutePath) throws -> ProjectDescription.TuistConfig

    /// Loads the Galaxy.swift in the given directory.
    ///
    /// - Parameter path: Path to the directory that contains the Galaxy.swift file.
    /// - Returns: Loaded Galaxy.swift file.
    /// - Throws: An error if the file has a syntax error.
    func loadGalaxy(at path: AbsolutePath) throws -> ProjectDescription.Galaxy

    func loadProject(at path: AbsolutePath) throws -> ProjectDescription.Project
    func loadWorkspace(at path: AbsolutePath) throws -> ProjectDescription.Workspace
    func loadSetup(at path: AbsolutePath) throws -> [Upping]
    func manifests(at path: AbsolutePath) -> Set<Manifest>
    func manifestPath(at path: AbsolutePath, manifest: Manifest) throws -> AbsolutePath
}

class GraphManifestLoader: GraphManifestLoading {
    // MARK: - Attributes

    let resourceLocator: ResourceLocating
    let projectDescriptionHelpersBuilder: ProjectDescriptionHelpersBuilding
    let manifestFilesLocator: ManifestFilesLocating
    private let decoder: JSONDecoder

    // MARK: - Init

    init(resourceLocator: ResourceLocating = ResourceLocator(),
         projectDescriptionHelpersBuilder: ProjectDescriptionHelpersBuilding = ProjectDescriptionHelpersBuilder(),
         manifestFilesLocator: ManifestFilesLocating = ManifestFilesLocator()) {
        self.resourceLocator = resourceLocator
        self.projectDescriptionHelpersBuilder = projectDescriptionHelpersBuilder
        self.manifestFilesLocator = manifestFilesLocator
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
        Set(manifestFilesLocator.locate(at: path).map { $0.0 })
    }

    func loadTuistConfig(at path: AbsolutePath) throws -> ProjectDescription.TuistConfig {
        try loadManifest(.tuistConfig, at: path)
    }

    func loadGalaxy(at path: AbsolutePath) throws -> ProjectDescription.Galaxy {
        try loadManifest(.galaxy, at: path)
    }

    func loadProject(at path: AbsolutePath) throws -> ProjectDescription.Project {
        try loadManifest(.project, at: path)
    }

    func loadWorkspace(at path: AbsolutePath) throws -> ProjectDescription.Workspace {
        try loadManifest(.workspace, at: path)
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
        let projectDesciptionHelpersModulePath = try projectDescriptionHelpersBuilder.build(at: path, projectDescriptionPath: projectDescriptionPath)
        if let projectDesciptionHelpersModulePath = projectDesciptionHelpersModulePath {
            arguments.append(contentsOf: [
                "-I", projectDesciptionHelpersModulePath.parentDirectory.pathString,
                "-L", projectDesciptionHelpersModulePath.parentDirectory.pathString,
                "-F", projectDesciptionHelpersModulePath.parentDirectory.pathString,
                "-lProjectDescriptionHelpers",
            ])
        }

        arguments.append(path.pathString)
        arguments.append("--tuist-dump")

        let result = try System.shared.capture(arguments).spm_chuzzle()
        guard let jsonString = result, let data = jsonString.data(using: .utf8) else {
            throw GraphManifestLoaderError.unexpectedOutput(path)
        }

        return data
    }
}
