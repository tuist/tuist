import Basic
import Foundation

class Settings {
    class Configuration {
        let settings: [String: String]
        let xcconfig: AbsolutePath?

        init(settings: [String: String] = [:], xcconfig: AbsolutePath? = nil) {
            self.settings = settings
            self.xcconfig = xcconfig
        }

        init(json: JSON, projectPath: AbsolutePath, context: GraphLoaderContexting) throws {
            settings = try json.get("settings")
            let xcconfigString: String? = json.get("xcconfig")
            xcconfig = xcconfigString.flatMap({ projectPath.appending(component: $0) })
            if let xcconfig = xcconfig, !context.fileHandler.exists(xcconfig) {
                throw GraphLoadingError.missingFile(xcconfig)
            }
        }
    }

    let base: [String: String]
    let debug: Configuration?
    let release: Configuration?

    init(base: [String: String] = [:],
         debug: Configuration?,
         release: Configuration?) {
        self.base = base
        self.debug = debug
        self.release = release
    }

    init(json: JSON, projectPath: AbsolutePath, context: GraphLoaderContexting) throws {
        base = try json.get("base")
        let debugJSON: JSON? = try json.get("debug")
        debug = try debugJSON.flatMap({ try Configuration(json: $0, projectPath: projectPath, context: context) })
        let releaseJSON: JSON? = try json.get("release")
        release = try releaseJSON.flatMap({ try Configuration(json: $0, projectPath: projectPath, context: context) })
    }
}
