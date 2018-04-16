import Foundation
import PathKit
import SwiftShell

protocol GraphManifestLoading {
    func load(path: Path) throws -> Data
}

class GraphManifestLoader: GraphManifestLoading {
    func load(path: Path) throws -> Data {
        let swiftOutput = run(bash: "xcrun -f swift")
        if let error = swiftOutput.error {
            throw error
        }
        let swiftPath = Path(swiftOutput.stdout)
        guard let frameworksPath = Bundle.app.privateFrameworksPath.map({ Path($0) }) else {
            throw "Can't find xcbuddy frameworks folder"
        }
        let projectDescriptionPath = frameworksPath + "ProjectDescription.framework"
        if !projectDescriptionPath.exists {
            throw "Couldn't find ProjectDescription.framework at \(projectDescriptionPath)"
        }
        let jsonOutput = run(bash: "\(swiftPath.string) -F \(frameworksPath.string) -framework ProjectDescription \(path.string) --dump")
        if let error = jsonOutput.error {
            throw error
        }
        return jsonOutput.stdout.data(using: .utf8) ?? Data()
    }
}
