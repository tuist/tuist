import Basic
import Foundation

/// Represents project or target build settings.
class Settings: GraphJSONInitiatable, Equatable {
    /// Settings configuration object that contains a reference to an .xcconfig file and a dictionary with the settings.
    class Configuration: Equatable {
        /// Build settings.
        let settings: [String: String]

        /// Path to an .xcconfig file.
        let xcconfig: AbsolutePath?

        /// Initializes the Configuration  object with its properties.
        ///
        /// - Parameters:
        ///   - settings: build settings.
        ///   - xcconfig: path to an .xcconfig file that contains the build settings.
        init(settings: [String: String] = [:], xcconfig: AbsolutePath? = nil) {
            self.settings = settings
            self.xcconfig = xcconfig
        }

        /// Initializes the Configuration from its JSON representation.
        ///
        /// - Parameters:
        ///   - json: Configuration JSON representation.
        ///   - projectPath: path to the folder that contains the project's manifest.
        ///   - context: graph loader  context.
        /// - Throws: an error if build files cannot be parsed.
        init(json: JSON, projectPath: AbsolutePath, context: GraphLoaderContexting) throws {
            settings = try json.get("settings")
            let xcconfigString: String? = json.get("xcconfig")
            xcconfig = xcconfigString.flatMap({ projectPath.appending(component: $0) })
            if let xcconfig = xcconfig, !context.fileHandler.exists(xcconfig) {
                throw GraphLoadingError.missingFile(xcconfig)
            }
        }

        /// Compares two configurations.
        ///
        /// - Parameters:
        ///   - lhs: first configuration to be compared.
        ///   - rhs: second configuration to be compared.
        /// - Returns: true  if  the two configurations are the same.
        static func == (lhs: Configuration, rhs: Configuration) -> Bool {
            return lhs.settings == rhs.settings && lhs.xcconfig == rhs.xcconfig
        }
    }

    /// Base build settings.
    let base: [String: String]

    /// Debug build settings.
    let debug: Configuration?

    /// Release build settings.
    let release: Configuration?

    /// Initializes the settings with its properties.
    ///
    /// - Parameters:
    ///   - base: base build settings.
    ///   - debug: debug build settings.
    ///   - release: relese build settings.
    init(base: [String: String] = [:],
         debug: Configuration?,
         release: Configuration?) {
        self.base = base
        self.debug = debug
        self.release = release
    }

    /// Initializes the Settings from its JSON representation.
    ///
    /// - Parameters:
    ///   - json: Configuration JSON representation.
    ///   - projectPath: path to the folder that contains the project's manifest.
    ///   - context: graph loader  context.
    /// - Throws: an error if build files cannot be parsed.
    required init(json: JSON, projectPath: AbsolutePath, context: GraphLoaderContexting) throws {
        base = try json.get("base")
        let debugJSON: JSON? = try json.get("debug")
        debug = try debugJSON.flatMap({ try Configuration(json: $0, projectPath: projectPath, context: context) })
        let releaseJSON: JSON? = try json.get("release")
        release = try releaseJSON.flatMap({ try Configuration(json: $0, projectPath: projectPath, context: context) })
    }

    /// Compares two Settings.
    ///
    /// - Parameters:
    ///   - lhs: first Settings to be compared.
    ///   - rhs: second Settings to be compared.
    /// - Returns: true if the Settings are  the same.
    static func == (lhs: Settings, rhs: Settings) -> Bool {
        return lhs.debug == rhs.debug &&
            lhs.release == rhs.release &&
            lhs.base == rhs.base
    }
}
