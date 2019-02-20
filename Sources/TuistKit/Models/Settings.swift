import Basic
import Foundation
import TuistCore

typealias BuildSettings = [String: String]

class Configuration: Equatable {
    
    typealias Name = String
    // MARK: - Attributes

    let name: String
    let buildConfiguration: BuildConfiguration
    let settings: BuildSettings
    let xcconfig: AbsolutePath?

    // MARK: - Init

    init(name: String, buildConfiguration: BuildConfiguration, settings: BuildSettings = [:], xcconfig: AbsolutePath? = nil) {
        self.name = name
        self.buildConfiguration = buildConfiguration
        self.settings = settings
        self.xcconfig = xcconfig
    }

    init(json: JSON, projectPath: AbsolutePath, fileHandler _: FileHandling) throws {
        name = try json.get("name")
        buildConfiguration = BuildConfiguration(rawValue: try json.get("buildConfiguration")) ?? .debug
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

    let base: BuildSettings
    let configurations: [Configuration]

    // MARK: - Init

    init(base: BuildSettings = [:], configurations: [Configuration]) {
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
        return lhs.base == rhs.base && lhs.configurations == rhs.configurations
    }
}

class TargetSettings: GraphInitiatable, Equatable {
    
    public let base: BuildSettings
    public let buildSettings: [Configuration.Name: BuildSettings]
    
    public init(base: BuildSettings, buildSettings: [Configuration.Name: BuildSettings]) {
        self.base = base
        self.buildSettings = buildSettings
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
        buildSettings = try dictionary.get("buildsSettings").mapValues{ try $0.getDictionary() }
    }
    
    // MARK: - Equatable
    
    static func == (lhs: TargetSettings, rhs: TargetSettings) -> Bool {
        return lhs.buildSettings == rhs.buildSettings
    }
    
}

extension JSON {
    
    /// Returns a JSON mappable dictionary for self.
    func getDictionary<T: JSONMappable>() throws -> [String: T] {
        guard case .dictionary(let value) = self else {
            throw MapError.typeMismatch(key: "<self>", expected: Dictionary<String, T>.self, json: self)
        }
        return try Dictionary(items: value.map({ ($0.0, try T.init(json: $0.1)) }))
    }
    
}
