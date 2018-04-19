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

        init(json: JSON, context: GraphLoaderContexting) throws {
            settings = try json.get("settings")
            let xcconfigString: String? = json.get("xcconfig")
            xcconfig = xcconfigString.flatMap({ context.path.appending(component: $0) })
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

    init(json: JSON, context: GraphLoaderContexting) throws {
        base = try json.get("base")
        let debugJSON: JSON? = try json.get("debug")
        debug = try debugJSON.flatMap({ try Configuration(json: $0, context: context) })
        let releaseJSON: JSON? = try json.get("release")
        release = try releaseJSON.flatMap({ try Configuration(json: $0, context: context) })
    }
}
