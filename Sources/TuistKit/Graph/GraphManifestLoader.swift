import Basic
import Foundation
import TuistCore

enum GraphManifestLoaderError: FatalError, Equatable {
    case projectDescriptionNotFound(AbsolutePath)
    case unexpectedOutput(AbsolutePath)
    case manifestNotFound(Manifest?, AbsolutePath)
    case setupNotFound(AbsolutePath)

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
        case let .setupNotFound(path):
            return "Setup.swift not found at path \(path.asString)"
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
        case .setupNotFound:
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
        case let (.setupNotFound(lhsPath), .setupNotFound(rhsPath)):
            return lhsPath == rhsPath
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
    func load(_ manifest: Manifest, path: AbsolutePath) throws -> JSON
    func manifests(at path: AbsolutePath) -> Set<Manifest>
    func manifestPath(at path: AbsolutePath, manifest: Manifest) throws -> AbsolutePath
    func loadSetup(at path: AbsolutePath) throws -> [Upping]
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
    }

    func load(_ manifest: Manifest, path: AbsolutePath) throws -> JSON {
        let manifestPath = try self.manifestPath(at: path, manifest: manifest)
        return try loadManifest(path: manifestPath)
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

    func loadSetup(at path: AbsolutePath) throws -> [Upping] {
        let setupPath = path.appending(component: "Setup.swift")
        guard fileHandler.exists(setupPath) else {
            throw GraphManifestLoaderError.setupNotFound(path)
        }

        let setup = try loadManifest(path: setupPath)
        let actionsJson: [JSON] = try setup.get("actions")
        return try actionsJson.compactMap {
            try Up.with(dictionary: $0,
                        projectPath: path,
                        fileHandler: fileHandler) }
    }

    // MARK: - Fileprivate

    fileprivate func loadManifest(path: AbsolutePath) throws -> JSON {
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

        guard let jsonString = try system.capture(arguments).spm_chuzzle() else {
            throw GraphManifestLoaderError.unexpectedOutput(path)
        }
        return try JSON(string: jsonString)
    }
}
