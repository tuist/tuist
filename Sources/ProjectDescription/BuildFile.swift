import Foundation

/// Sources build phase files.
public class SourcesBuildFile: ExpressibleByStringLiteral, JSONConvertible {
    /// Pattern
    let pattern: String

    /// Compiler flags.
    let compilerFlags: String?

    /// Default sources build file constructor.
    ///
    /// - Parameters:
    ///   - pattern: pattern.
    ///   - compilerFlags: compiler flags.
    init(_ pattern: String, compilerFlags: String? = nil) {
        self.pattern = pattern
        self.compilerFlags = compilerFlags
    }

    /// Convenience static method to return a new sources build phase.
    ///
    /// - Parameters:
    ///   - pattern: path pattern (it supports glob)
    ///   - compilerFlags: compiler flags.
    /// - Returns: sources build file.
    public static func sources(_ pattern: String, compilerFlags: String? = nil) -> SourcesBuildFile {
        return SourcesBuildFile(pattern,
                                compilerFlags: compilerFlags)
    }

    // MARK: - ExpressibleByStringLiteral

    public required init(stringLiteral value: String) {
        pattern = value
        compilerFlags = nil
    }

    public required convenience init(extendedGraphemeClusterLiteral value: String) {
        self.init(stringLiteral: value)
    }

    /// Returns a JSON representation of the object.
    ///
    /// - Returns: JSON representation.
    func toJSON() -> JSON {
        var dictionary: [String: JSON] = [:]
        dictionary["pattern"] = pattern.toJSON()
        if let compilerFlags = compilerFlags {
            dictionary["compiler_flags"] = compilerFlags.toJSON()
        }
        return JSON.dictionary(dictionary)
    }
}

/// Resources build file.
public class ResourcesBuildFile: JSONConvertible {
    /// Returns a resource build file.
    ///
    /// - Parameter pattern: path pattern (it supports glob).
    /// - Returns: resources build file.
    public static func resources(_ pattern: String) -> ResourcesBuildFile {
        return BaseResourcesBuildFile(pattern)
    }

    public static func coreDataModel(_ path: String, currentVersion: String) -> ResourcesBuildFile {
        return CoreDataModelBuildFile(path, currentVersion: currentVersion)
    }

    /// Returns a JSON representation of the object.
    ///
    /// - Returns: JSON representation.
    func toJSON() -> JSON {
        fatalError("This method should be overriden")
    }
}

/// Base resources build file.
class BaseResourcesBuildFile: ResourcesBuildFile {
    /// Pattern.
    let pattern: String

    /// Initialzies the build file with its attributes.
    ///
    /// - Parameter pattern: path pattern.
    init(_ pattern: String) {
        self.pattern = pattern
    }

    /// Returns a JSON representation of the object.
    ///
    /// - Returns: JSON representation.
    override func toJSON() -> JSON {
        return JSON.dictionary([
            "type": "default".toJSON(),
            "pattern": self.pattern.toJSON(),
        ])
    }
}

/// Core data model build file.
class CoreDataModelBuildFile: ResourcesBuildFile {
    /// Relative path to the model.
    let path: String

    /// Current version (with or without extension)
    let currentVersion: String

    /// Initializes the build file with its attributes.
    ///
    /// - Parameters:
    ///   - path: relative path to the Core Data model.
    ///   - currentVersion: current version name (with or without the extension).
    init(_ path: String,
         currentVersion: String) {
        self.path = path
        self.currentVersion = currentVersion
    }

    /// Returns a JSON representation of the object.
    ///
    /// - Returns: JSON representation.
    override func toJSON() -> JSON {
        return JSON.dictionary([
            "type": "core_data".toJSON(),
            "path": self.path.toJSON(),
            "current_version": self.currentVersion.toJSON(),
        ])
    }
}

/// Headers build file.
public class HeadersBuildFile: JSONConvertible {
    /// Header access level.
    ///
    /// - `public`: public.
    /// - `private`: private.
    /// - project: project.
    enum AccessLevel: String {
        case `public`, `private`, project
    }

    /// Pattern.
    let pattern: String

    /// Access level.
    let accessLevel: AccessLevel

    /// Initializes the headers build file with its attributes.
    ///
    /// - Parameters:
    ///   - pattern: pattern (it supports glob).
    ///   - accessLevel: access level.
    init(_ pattern: String, accessLevel: AccessLevel) {
        self.pattern = pattern
        self.accessLevel = accessLevel
    }

    /// Returns a headers build file with a public access level.
    ///
    /// - Parameter pattern: path pattern (it supports glob).
    /// - Returns: headers build file.
    public static func `public`(_ pattern: String) -> HeadersBuildFile {
        return HeadersBuildFile(pattern, accessLevel: .public)
    }

    /// Returns a headers build file with a private access level.
    ///
    /// - Parameter pattern: path pattern (it supports glob).
    /// - Returns: headers build file.
    public static func `private`(_ pattern: String) -> HeadersBuildFile {
        return HeadersBuildFile(pattern, accessLevel: .private)
    }

    /// Returns a headers build file with a project access level.
    ///
    /// - Parameter pattern: path pattern (it supports glob).
    /// - Returns: headers build file.
    public static func project(_ pattern: String) -> HeadersBuildFile {
        return HeadersBuildFile(pattern, accessLevel: .project)
    }

    /// Returns a JSON representation of the object.
    ///
    /// - Returns: JSON representation.
    func toJSON() -> JSON {
        return JSON.dictionary([
            "pattern": pattern.toJSON(),
            "access_level": accessLevel.rawValue.toJSON(),
        ])
    }
}
