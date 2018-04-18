import Basic
import Foundation

protocol GraphManifestLoading {
    func load(path: AbsolutePath, context: GraphLoaderContexting) throws -> JSON
}

class GraphManifestLoader: GraphManifestLoading {
    func load(path: AbsolutePath, context: GraphLoaderContexting) throws -> JSON {
        guard let swiftOutput = try run("xcrun", "-f", "swift").chuzzle() else {
            throw GraphLoadingError.unexpected("Couldn't find swift binary")
        }
        let swiftPath = AbsolutePath(swiftOutput)
        guard let frameworksPath = Bundle.app.privateFrameworksPath.map({ AbsolutePath($0) }) else {
            throw "Can't find xcbuddy frameworks folder"
        }
        let projectDescriptionPath = frameworksPath.appending(component: "ProjectDescription.framework")
        if !context.fileHandler.exists(projectDescriptionPath) {
            throw "Couldn't find ProjectDescription.framework at \(projectDescriptionPath)"
        }
        guard let jsonString = try run(swiftPath.asString, "-F", frameworksPath.asString, "-framework", "ProjectDescription", path.asString, "--dump").chuzzle() else {
            throw GraphLoadingError.unexpected("Couldn't read manifest at path \(path.asString)")
        }
        return try JSON(string: jsonString)
    }

    func run(_ args: String...) throws -> String {
        let result = try Process.popen(arguments: args)
        return try result.utf8Output()
    }
}
