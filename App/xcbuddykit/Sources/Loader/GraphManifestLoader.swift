import Basic
import Foundation

protocol GraphManifestLoading {
    func load(path: AbsolutePath, context: GraphLoaderContexting) throws -> JSON
}

class GraphManifestLoader: GraphManifestLoading {
    func load(path: AbsolutePath, context: GraphLoaderContexting) throws -> JSON {
        let swiftOutput = try run(bash: "xcrun -f swift")
        let swiftPath = AbsolutePath(swiftOutput)
        guard let frameworksPath = Bundle.app.privateFrameworksPath.map({ AbsolutePath($0) }) else {
            throw "Can't find xcbuddy frameworks folder"
        }
        let projectDescriptionPath = frameworksPath.appending(component: "ProjectDescription.framework")
        if !context.fileHandler.exists(projectDescriptionPath) {
            throw "Couldn't find ProjectDescription.framework at \(projectDescriptionPath)"
        }
        let jsonString = try run(bash: "\(swiftPath.asString) -F \(frameworksPath.asString) -framework ProjectDescription \(path.asString) --dump")
        return try JSON(string: jsonString)
    }

    func run(bash: String) throws -> String {
        let process = Process(args: "/bin/bash -c '\(bash)'")
        try process.launch()
        let output = try process.waitUntilExit()
        return try output.utf8Output()
    }
}
