import Basic
import Foundation
import TuistCore

class Configuration: Equatable {
    // MARK: - Attributes

    let name: String
    let type: BuildConfiguration
    let settings: [String: String]
    let xcconfig: AbsolutePath?

    // MARK: - Init

    init(name: String, type: BuildConfiguration, settings: [String: String] = [:], xcconfig: AbsolutePath? = nil) {
        self.name = name
        self.type = type
        self.settings = settings
        self.xcconfig = xcconfig
    }

    init(json: JSON, projectPath: AbsolutePath, fileHandler _: FileHandling) throws {
        name = try json.get("name")
        type = BuildConfiguration(rawValue: try json.get("type"))! //FIXME Don't force unwrap
        settings = try json.get("settings")
        let xcconfigString: String? = json.get("xcconfig")
        xcconfig = xcconfigString.flatMap({ projectPath.appending(RelativePath($0)) })
    }

    // MARK: - Equatable

    static func == (lhs: Configuration, rhs: Configuration) -> Bool {
        return lhs.settings == rhs.settings && lhs.xcconfig == rhs.xcconfig
    }
}

class Settings: Equatable {
    // MARK: - Attributes

    let base: [String: String]
    let configurations: [Configuration]

    // MARK: - Init

    init(base: [String: String] = [:],
         configurations: [Configuration]) {
        self.base = base
        self.configurations = configurations
    }

    /// Default constructor of entities that are part of the manifest.
    ///
    /// - Parameters:
    ///   - dictionary: Dictionary with the object representation.
    ///   - projectPath: Absolute path to the folder that contains the manifest.
    ///     This is useful to obtain absolute paths from the relative paths provided in the manifest by the user.
    ///   - fileHandler: File handler for any file operations like checking whether a file exists or not.
    /// - Throws: A decoding error if an expected property is missing or has an invalid value.
    required init(dictionary: JSON, projectPath: AbsolutePath, fileHandler: FileHandling) throws {
        base = try dictionary.get("base")
        configurations = try dictionary.getArray("configurations").compactMap({ try Configuration(json: $0, projectPath: projectPath, fileHandler: fileHandler) })
    }

    // MARK: - Equatable

    static func == (lhs: Settings, rhs: Settings) -> Bool {
        return lhs.base == rhs.base &&
            lhs.configurations == rhs.configurations
    }
}
//
//class TargetSettings: GraphInitiatable, Equatable {
//    // MARK: - Attributes
//
//    let base: [String: String]
//    let debug: Configuration
//    let release: Configuration
//
//    // MARK: - Init
//
//    init(base: [String: String] = [:], debug: Configuration = Configuration(name: "Debug", type: .debug), release: Configuration = Configuration(name: "Release", type: .release)) {
//        self.base = base
//        self.debug = debug
//        self.release = release
//    }
//
//    /// Default constructor of entities that are part of the manifest.
//    ///
//    /// - Parameters:
//    ///   - dictionary: Dictionary with the object representation.
//    ///   - projectPath: Absolute path to the folder that contains the manifest.
//    ///     This is useful to obtain absolute paths from the relative paths provided in the manifest by the user.
//    ///   - fileHandler: File handler for any file operations like checking whether a file exists or not.
//    /// - Throws: A decoding error if an expected property is missing or has an invalid value.
//    required init(dictionary: JSON, projectPath: AbsolutePath, fileHandler: FileHandling) throws {
//        base = try dictionary.get("base")
//        let debugJSON: JSON? = try? dictionary.get("debug")
//        debug = try debugJSON.flatMap{ _ in try Configuration(name: "Debug", type: .debug, settings: [String:String](), xcconfig: nil) }!
//        let releaseJSON: JSON? = try? dictionary.get("release")
//        release = try releaseJSON.flatMap{ _ in try Configuration(name: "Release", type: .release, settings: [String:String](), xcconfig: nil) }!
////        configurations = try dictionary.getArray("configurations").compactMap{ try Configuration(json: $0, projectPath: projectPath, fileHandler: fileHandler) }
//    }
//
//    // MARK: - Equatable
//
//    static func == (lhs: TargetSettings, rhs: TargetSettings) -> Bool {
//        return lhs.base == rhs.base &&
//            lhs.debug == rhs.debug
//    }
//}
