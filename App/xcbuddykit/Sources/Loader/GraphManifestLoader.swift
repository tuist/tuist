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
/// - swiftNotFound: error thrown when Swift is not found in the system.
/// - unexpectedOutput: error throw when we get an unexpected output trying to compile the manifest.
enum GraphManifestLoaderError: Error, ErrorStringConvertible, Equatable {
    case projectDescriptionNotFound(AbsolutePath)
    case frameworksFolderNotFound
    case swiftNotFound
    case unexpectedOutput(AbsolutePath)

    var errorDescription: String {
        switch self {
        case let .projectDescriptionNotFound(path):
            return "Couldn't find ProjectDescription.framework at path \(path.asString)."
        case .frameworksFolderNotFound:
            return "Couldn't find the Frameworks folder in the bundle that contains the ProjectDescription.framework."
        case .swiftNotFound:
            return "Couldn't find Swift on your environment. Run 'xcode-select -p' to see if the Xcode path is properly setup."
        case let .unexpectedOutput(path):
            return "Unexpected output trying to parse the manifest at path \(path.asString)."
        }
    }

    static func == (lhs: GraphManifestLoaderError, rhs: GraphManifestLoaderError) -> Bool {
        switch (lhs, rhs) {
        case let (.projectDescriptionNotFound(lhsPath), .projectDescriptionNotFound(rhsPath)):
            return lhsPath == rhsPath
        case (.frameworksFolderNotFound, .frameworksFolderNotFound): return true
        case (.swiftNotFound, .swiftNotFound): return true
        case let (.unexpectedOutput(lhsPath), .unexpectedOutput(rhsPath)):
            return lhsPath == rhsPath
        default:
            return false
        }
    }
}

/// Graph manifest loader.
class GraphManifestLoader: GraphManifestLoading {
    /// Loads the manifest at the given path.
    ///
    /// - Parameters:
    ///   - path: path to the manifest file (it needs to be a .swift file)
    ///   - context: graph loader context.
    /// - Returns: jSON representation of the manifest.
    /// - Throws: an error if the manifest cannot be loaded.
    func load(path: AbsolutePath, context: GraphLoaderContexting) throws -> JSON {
        guard let swiftOutput = try context.shell.run("xcrun", "-f", "swift").chuzzle() else {
            throw GraphManifestLoaderError.swiftNotFound
        }
        let swiftPath = AbsolutePath(swiftOutput)
        let manifestFrameworkPath = try context.resourceLocator.projectDescription()
        let jsonString: String! = try context.shell.run(swiftPath.asString, "-F",
                                                        manifestFrameworkPath.parentDirectory.asString,
                                                        "-framework", "ProjectDescription",
                                                        path.asString, "--dump").chuzzle()
        if jsonString == nil {
            throw GraphManifestLoaderError.unexpectedOutput(path)
        }
        let json = try JSON(string: jsonString)
        return json
    }
}
