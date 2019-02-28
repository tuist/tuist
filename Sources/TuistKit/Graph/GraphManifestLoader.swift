import Basic
import Foundation
import TuistCore
import ProjectDescription

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
            return "Couldn't find ProjectDescription.framework at path \(path.asString)"
        case let .unexpectedOutput(path):
            return "Unexpected output trying to parse the manifest at path \(path.asString)"
        case let .manifestNotFound(manifest, path):
            return "\(manifest?.fileName ?? "Manifest") not found at path \(path.asString)"
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
    case setup

    var fileName: String {
        switch self {
        case .project:
            return "Project.swift"
        case .workspace:
            return "Workspace.swift"
        case .setup:
            return "Setup.swift"
        }
    }
}

protocol GraphManifestLoading {
    func loadProject(at path: AbsolutePath) throws -> ProjectDescription.Project
    func loadWorkspace(at path: AbsolutePath) throws -> ProjectDescription.Workspace
    func loadSetup(at path: AbsolutePath) throws -> [Upping]
    func manifests(at path: AbsolutePath) -> Set<Manifest>
    func manifestPath(at path: AbsolutePath, manifest: Manifest) throws -> AbsolutePath
}

class GraphManifestLoader: GraphManifestLoading {
    // MARK: - Attributes

    /// File handler to interact with the file system.
    let fileHandler: FileHandling

    /// Instance to run commands in the system.
    let system: Systeming

    /// Resource locator to look up Tuist-related resources.
    let resourceLocator: ResourceLocating

    /// Depreactor to notify about deprecations.
    let deprecator: Deprecating
    
    /// A decoder instance for decoding the raw manifest data to their concrete types
    private let decoder: JSONDecoder
    
    // MARK: - Init

    /// Initializes the manifest loader with its attributes.
    ///
    /// - Parameters:
    ///   - fileHandler: File handler to interact with the file system.
    ///   - system: Instance to run commands in the system.
    ///   - resourceLocator: Resource locator to look up Tuist-related resources.
    ///   - deprecator: Depreactor to notify about deprecations.
    init(fileHandler: FileHandling = FileHandler(),
         system: Systeming = System(),
         resourceLocator: ResourceLocating = ResourceLocator(),
         deprecator: Deprecating = Deprecator()) {
        self.fileHandler = fileHandler
        self.system = system
        self.resourceLocator = resourceLocator
        self.deprecator = deprecator
        self.decoder = JSONDecoder()
    }

    func manifestPath(at path: AbsolutePath, manifest: Manifest) throws -> AbsolutePath {
        let filePath = path.appending(component: manifest.fileName)

        if fileHandler.exists(filePath) {
            return filePath
        } else {
            throw GraphManifestLoaderError.manifestNotFound(manifest, path)
        }
    }

    func manifests(at path: AbsolutePath) -> Set<Manifest> {
        return .init(Manifest.allCases.filter {
            fileHandler.exists(path.appending(component: $0.fileName))
        })
    }

    func loadProject(at path: AbsolutePath) throws -> ProjectDescription.Project {
        return try loadManifest(.project, at: path)
    }
    
    func loadWorkspace(at path: AbsolutePath) throws -> ProjectDescription.Workspace {
        return try loadManifest(.workspace, at: path)
    }
    
    func loadSetup(at path: AbsolutePath) throws -> [Upping] {
        let setupPath = path.appending(component: Manifest.setup.fileName)
        guard fileHandler.exists(setupPath) else {
            throw GraphManifestLoaderError.manifestNotFound(.setup, path)
        }

        let setup = try loadManifestData(at: setupPath)
        let setupJson = try JSON(data: setup)
        let actionsJson: [JSON] = try setupJson.get("actions")
        return try actionsJson.compactMap {
            try Up.with(dictionary: $0,
                        projectPath: path,
                        fileHandler: fileHandler) }
    }

    // MARK: - Private

    private func loadManifest<T: Decodable>(_ manifest: Manifest, at path: AbsolutePath) throws -> T {
        let manifestPath = path.appending(component: manifest.fileName)
        guard fileHandler.exists(manifestPath) else {
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
            "-I", projectDescriptionPath.parentDirectory.asString,
            "-L", projectDescriptionPath.parentDirectory.asString,
            "-F", projectDescriptionPath.parentDirectory.asString,
            "-lProjectDescription",
        ]
        arguments.append(path.asString)
        arguments.append("--dump")

        guard let jsonString = try system.capture(arguments).spm_chuzzle(),
            let data = jsonString.data(using: .utf8) else {
            throw GraphManifestLoaderError.unexpectedOutput(path)
        }
        
        return data
    }
}
