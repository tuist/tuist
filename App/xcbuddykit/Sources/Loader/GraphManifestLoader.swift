import Foundation
import Basic

protocol GraphManifestLoading {
    func load(path: AbsolutePath, context: GraphLoaderContexting) throws -> String
}

class GraphManifestLoader: GraphManifestLoading {
    func load(path: AbsolutePath, context: GraphLoaderContexting) throws -> String {
        
        let swiftOutput = try run(bash: "xcrun -f swift")
        let swiftPath = AbsolutePath(swiftOutput)
        guard let frameworksPath = Bundle.app.privateFrameworksPath.map({ AbsolutePath($0) }) else {
            throw "Can't find xcbuddy frameworks folder"
        }
        let projectDescriptionPath = frameworksPath.appending(component: "ProjectDescription.framework")
        if !context.fileHandler.exists(projectDescriptionPath) {
            throw "Couldn't find ProjectDescription.framework at \(projectDescriptionPath)"
        }
        return try run(bash: "\(swiftPath.asString) -F \(frameworksPath.asString) -framework ProjectDescription \(path.asString) --dump")
    }
    
    func run(bash: String) throws -> String {
        let process = Process(arguments: ["/bin/bash -c '\(bash)'"], environment: [:], redirectOutput: true)
        try process.launch()
        let output = try process.waitUntilExit()
        return try output.utf8Output()
    }
}
