import Basic
import Foundation

/// Protocol that defines the interface of an object that can read a manifest file from the disk.
/// A manifest file is a Swift file that gets compiled and that outputs a JSON to the console.
/// Examples of manifests are Project.swift or Workspace.swift.
protocol GraphManifestLoading {
    func load(path: AbsolutePath, context: GraphLoaderContexting) throws -> JSON
}

/// Errors thrown during the manifest loading.
///
/// - projectDescriptionNotFound: error thrown when the ProjectDescription.framework cannot be cound.
/// - frameworksFolderNotFound: error thrown when the frameworks fodler that contains the ProjectDescription.framework cannot be found.
/// - unexpectedOutput: error throw when we get an unexpected output trying to compile the manifest.
enum GraphManifestLoaderError: FatalError {
    case projectDescriptionNotFound(AbsolutePath)
    case frameworksFolderNotFound
    case unexpectedOutput(AbsolutePath)

    /// Error description.
    var description: String {
        switch self {
        case let .projectDescriptionNotFound(path):
            return "Couldn't find ProjectDescription.framework at path \(path.asString)."
        case .frameworksFolderNotFound:
            return "Couldn't find the Frameworks folder in the bundle that contains the ProjectDescription.framework."
        case let .unexpectedOutput(path):
            return "Unexpected output trying to parse the manifest at path \(path.asString)."
        }
    }

    /// Error type.
    var type: ErrorType {
        switch self {
        case .unexpectedOutput:
            return .bug
        default:
            return .abort
        }
    }

    /// Compares two GraphManifestLoading instances.
    ///
    /// - Parameters:
    ///   - lhs: first instance to be compared.
    ///   - rhs: second instance to be compared.
    /// - Returns: true if the two instances are the same.
    static func == (lhs: GraphManifestLoaderError, rhs: GraphManifestLoaderError) -> Bool {
        switch (lhs, rhs) {
        case let (.projectDescriptionNotFound(lhsPath), .projectDescriptionNotFound(rhsPath)):
            return lhsPath == rhsPath
        case (.frameworksFolderNotFound, .frameworksFolderNotFound): return true
        case let (.unexpectedOutput(lhsPath), .unexpectedOutput(rhsPath)):
            return lhsPath == rhsPath
        default:
            return false
        }
    }
}

/// Graph manifest loader.
class GraphManifestLoader: GraphManifestLoading {
    /// Module loader.
    let moduleLoader: GraphModuleLoading

    /// Initializes the loader with its attributes.
    ///
    /// - Parameter moduleLoader: module loader.
    init(moduleLoader: GraphModuleLoading = GraphModuleLoader()) {
        self.moduleLoader = moduleLoader
    }

    /// Loads the manifest at the given path.
    ///
    /// - Parameters:
    ///   - path: path to the manifest file (it needs to be a .swift file)
    ///   - context: graph loader context.
    /// - Returns: jSON representation of the manifest.
    /// - Throws: an error if the manifest cannot be loaded.
    func load(path: AbsolutePath, context: GraphLoaderContexting) throws -> JSON {
        let manifestFrameworkPath = try context.resourceLocator.projectDescription()
        var arguments: [String] = [
            "xcrun", "swift",
            "-module-name", "Manifest",
            "-F", manifestFrameworkPath.parentDirectory.asString,
            "-framework", "ProjectDescription",
        ]
        arguments.append(contentsOf: try moduleLoader.load(path, context: context).map({ $0.asString }))
        arguments.append("--dump")
        let jsonString: String! = try context.shell.run(arguments, environment: ["DUMP": "1"]).chuzzle()
        if jsonString == nil {
            throw GraphManifestLoaderError.unexpectedOutput(path)
        }
        let json = try JSON(string: jsonString)
        return json
    }
}
