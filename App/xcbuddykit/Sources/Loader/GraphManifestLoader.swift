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
/// - compileError: error trying to compile the manifest file, most likely because the syntax is not correct.
enum GraphManifestLoaderError: Error, CustomStringConvertible, Equatable {
    case projectDescriptionNotFound(AbsolutePath)
    case frameworksFolderNotFound
    case swiftNotFound
    case unexpectedOutput(AbsolutePath)
    case compileError(String)

    var description: String {
        switch self {
        case let .projectDescriptionNotFound(path):
            return "Couldn't find ProjectDescription.framework at path \(path.asString)."
        case .frameworksFolderNotFound:
            return "Couldn't find the Frameworks folder in the bundle that contains the ProjectDescription.framework."
        case .swiftNotFound:
            return "Couldn't find Swift on your environment. Run 'xcode-select -p' to see if the Xcode path is properly setup."
        case let .unexpectedOutput(path):
            return "Unexpected output trying to parse the manifest at path \(path.asString)."
        case let .compileError(error):
            return "Error trying to compile manifest: \(error)."
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
        case let (.compileError(lhsError), .compileError(rhsError)):
            return rhsError == lhsError
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
        guard let swiftOutput = try run("xcrun", "-f", "swift").chuzzle() else {
            throw GraphManifestLoaderError.swiftNotFound
        }
        let swiftPath = AbsolutePath(swiftOutput)
        let manifestFrameworkPath = try projectDescriptionPath(context: context)
        let jsonString: String! = try run(swiftPath.asString, "-F", manifestFrameworkPath.parentDirectory.asString, "-framework", "ProjectDescription", path.asString, "--dump").chuzzle()
        if jsonString == nil {
            throw GraphManifestLoaderError.unexpectedOutput(path)
        }
        let json = try JSON(string: jsonString)
        return json
    }

    /// Runs a bash command.
    ///
    /// - Parameter args: arguments.
    /// - Returns: command output as a string.
    /// - Throws: an error if the command execution fails.
    func run(_ args: String...) throws -> String {
        let result = try Process.popen(arguments: args)
        if result.exitStatus == .terminated(code: 0) {
            return try result.utf8Output()
        } else {
            throw GraphManifestLoaderError.compileError(try result.utf8stderrOutput())
        }
    }

    /// Returns the path where the ProjectDescription.framework is.
    ///
    /// - Parameter context: graph loader context.
    /// - Returns: ProjectDescription.framework path.
    /// - Throws: an error if the framework cannot be found.
    fileprivate func projectDescriptionPath(context: GraphLoaderContexting) throws -> AbsolutePath {
        let xcbuddyKitPath = AbsolutePath(Bundle(for: GraphManifestLoader.self).bundleURL.path)
        let xcbuddyKitParentPath = xcbuddyKitPath.parentDirectory
        let projectDescriptionPath = xcbuddyKitParentPath.appending(component: "ProjectDescription.framework")
        if context.fileHandler.exists(projectDescriptionPath) {
            return projectDescriptionPath
        } else {
            throw GraphManifestLoaderError.projectDescriptionNotFound(projectDescriptionPath)
        }
    }
}
