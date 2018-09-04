import Basic
import Foundation
import TuistCore
import Yams

enum GraphManifestLoaderError: FatalError, Equatable {
    case projectDescriptionNotFound(AbsolutePath)
    case unexpectedOutput(AbsolutePath)
    case invalidYaml(AbsolutePath)
    case manifestNotFound(Manifest, AbsolutePath)

    var description: String {
        switch self {
        case let .projectDescriptionNotFound(path):
            return "Couldn't find ProjectDescription.framework at path \(path.asString)"
        case let .unexpectedOutput(path):
            return "Unexpected output trying to parse the manifest at path \(path.asString)"
        case let .invalidYaml(path):
            return "Invalid yaml at path \(path.asString). The root element should be a dictionary"
        case let .manifestNotFound(manifest, path):
            return "\(manifest.fileName.capitalized) not found at \(path.asString)"
        }
    }

    var type: ErrorType {
        switch self {
        case .unexpectedOutput:
            return .bug
        case .projectDescriptionNotFound:
            return .bug
        case .invalidYaml:
            return .abort
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
        case let (.invalidYaml(lhsPath), .invalidYaml(rhsPath)):
            return lhsPath == rhsPath
        case let (.manifestNotFound(lhsManifest, lhsPath), .manifestNotFound(rhsManifest, rhsPath)):
            return lhsManifest == rhsManifest && lhsPath == rhsPath
        default:
            return false
        }
    }
}

enum Manifest {
    case project
    case workspace

    var fileName: String {
        switch self {
        case .project:
            return "Project"
        case .workspace:
            return "Workspace"
        }
    }

    static var supportedExtensions: Set<String> = Set(arrayLiteral: "json", "swift", "yaml", "yml")
}

protocol GraphManifestLoading {
    func load(_ manifest: Manifest, path: AbsolutePath) throws -> JSON
    func manifests(at path: AbsolutePath) -> Set<Manifest>
    func manifestPath(at path: AbsolutePath, manifest: Manifest) throws -> AbsolutePath
}

class GraphManifestLoader: GraphManifestLoading {
    // MARK: - Attributes

    let moduleLoader: GraphModuleLoading
    let fileAggregator: FileAggregating
    let fileHandler: FileHandling
    let system: Systeming
    let resourceLocator: ResourceLocating

    // MARK: - Init

    init(moduleLoader: GraphModuleLoading = GraphModuleLoader(),
         fileAggregator: FileAggregating = FileAggregator(),
         fileHandler: FileHandling = FileHandler(),
         system: Systeming = System(),
         resourceLocator: ResourceLocating = ResourceLocator()) {
        self.moduleLoader = moduleLoader
        self.fileAggregator = fileAggregator
        self.fileHandler = fileHandler
        self.system = system
        self.resourceLocator = resourceLocator
    }

    func load(_ manifest: Manifest, path: AbsolutePath) throws -> JSON {
        let manifestPath = try self.manifestPath(at: path, manifest: manifest)
        if manifestPath.extension == "swift" {
            return try loadSwiftManifest(path: manifestPath)
        } else if manifestPath.extension == "json" {
            return try loadJSONManifest(path: manifestPath)
        } else if manifestPath.extension == "yaml" || manifestPath.extension == "yml" {
            return try loadYamlManifest(path: manifestPath)
        } else {
            throw GraphManifestLoaderError.manifestNotFound(manifest, path)
        }
    }

    func manifestPath(at path: AbsolutePath, manifest: Manifest) throws -> AbsolutePath {
        let swiftPath = path.appending(component: "\(manifest.fileName).swift")
        let jsonPath = path.appending(component: "\(manifest.fileName).json")
        let yamlPath = path.appending(component: "\(manifest.fileName).yaml")
        let ymlPath = path.appending(component: "\(manifest.fileName).yml")

        if fileHandler.exists(swiftPath) {
            return swiftPath
        } else if fileHandler.exists(jsonPath) {
            return jsonPath
        } else if fileHandler.exists(yamlPath) {
            return yamlPath
        } else if fileHandler.exists(ymlPath) {
            return ymlPath
        } else {
            throw GraphManifestLoaderError.manifestNotFound(manifest, path)
        }
    }

    func manifests(at path: AbsolutePath) -> Set<Manifest> {
        let manifests: [Manifest] = [.project, .workspace].filter { manifest in
            let paths = Manifest.supportedExtensions.map {
                path.appending(component: "\(manifest.fileName).\($0)")
            }
            return paths.contains(where: { fileHandler.exists($0) })
        }
        return Set(manifests)
    }

    // MARK: - Fileprivate

    fileprivate func loadYamlManifest(path: AbsolutePath) throws -> JSON {
        let content = try String(contentsOf: path.url)
        guard let object = try Yams.load(yaml: content) as? [String: Any] else {
            throw GraphManifestLoaderError.invalidYaml(path)
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: [])
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return try JSON(string: json)
    }

    fileprivate func loadJSONManifest(path: AbsolutePath) throws -> JSON {
        let content = try String(contentsOf: path.url)
        return try JSON(string: content)
    }

    fileprivate func loadSwiftManifest(path: AbsolutePath) throws -> JSON {
        let projectDescriptionPath = try resourceLocator.projectDescription()
        var arguments: [String] = [
            "xcrun", "swiftc",
            "--driver-mode=swift",
            "-suppress-warnings",
            "-I", projectDescriptionPath.parentDirectory.asString,
            "-L", projectDescriptionPath.parentDirectory.asString,
            "-F", projectDescriptionPath.parentDirectory.asString,
            "-lProjectDescription",
        ]
        let file = try TemporaryFile()
        try fileAggregator.aggregate(moduleLoader.load(path).reversed(), into: file.path)
        arguments.append(file.path.asString)
        arguments.append("--dump")
        let result = try system.capture(arguments, verbose: false)
        try result.throwIfError()
        let jsonString: String! = result.stdout.chuzzle()
        if jsonString == nil {
            throw GraphManifestLoaderError.unexpectedOutput(path)
        }
        return try JSON(string: jsonString)
    }
}
