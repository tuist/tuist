import Basic
import Foundation

/// Build file error.
///
/// - invalidBuildFileType: the build file type is invalid.
enum BuildFileError: FatalError, Equatable {
    case invalidBuildFileType(String)

    /// Error type.
    var type: ErrorType {
        switch self {
        case .invalidBuildFileType:
            return .bugSilent
        }
    }

    /// Error description.
    var description: String {
        switch self {
        case let .invalidBuildFileType(type):
            return "Invalid build file type: \(type)"
        }
    }

    /// Returns true if the two instances of BuildFileError are equal.
    ///
    /// - Parameters:
    ///   - lhs: first instance to be compared.
    ///   - rhs: second instance to be compared.
    /// - Returns: true if the two instances are the same.
    static func == (lhs: BuildFileError, rhs: BuildFileError) -> Bool {
        switch (lhs, rhs) {
        case let (.invalidBuildFileType(lhsType), .invalidBuildFileType(rhsType)):
            return lhsType == rhsType
        }
    }
}

/// Sources build phase files.
class SourcesBuildFile: GraphJSONInitiatable, Equatable {
    /// Paths
    let paths: [AbsolutePath]

    /// Compiler flags.
    let compilerFlags: String?

    /// Initializes the sources build file with its attributes.
    ///
    /// - Parameters:
    ///   - paths: sources build file paths.
    ///   - compilerFlags: compiler flags.
    init(_ paths: [AbsolutePath] = [], compilerFlags: String? = nil) {
        self.paths = paths
        self.compilerFlags = compilerFlags
    }

    required init(json: JSON,
                  projectPath: AbsolutePath,
                  context _: GraphLoaderContexting) throws {
        compilerFlags = try? json.get("compiler_flags")
        let pattern: String = try json.get("pattern")
        paths = projectPath.glob(pattern)
    }

    /// Returns true if the two instances of SourcesBuildFile are equal.
    ///
    /// - Parameters:
    ///   - lhs: first instance to be compared.
    ///   - rhs: second instance to be compared.
    /// - Returns: true if the two instances are the same.
    static func == (lhs: SourcesBuildFile, rhs: SourcesBuildFile) -> Bool {
        return lhs.paths == rhs.paths &&
            lhs.compilerFlags == rhs.compilerFlags
    }
}

/// Base resources build file.
class BaseResourcesBuildFile: Equatable {
    /// Initializes a resources build file from its JSON representation.
    ///
    /// - Parameters:
    ///   - json: resources build file JSON.
    ///   - projectPath: path to the folder that contains the project manifest.
    ///   - context: graph loading context.
    /// - Returns: the initialized resources build phase.
    /// - Throws: an error if build file cannot be parsed.
    static func from(json: JSON,
                     projectPath: AbsolutePath,
                     context: GraphLoaderContexting) throws -> BaseResourcesBuildFile {
        let type: String = try json.get("type")
        if type == "core_data" {
            return try CoreDataModelBuildFile(json: json,
                                              projectPath: projectPath,
                                              context: context)
        } else if type == "default" {
            return try ResourcesBuildFile(json: json,
                                          projectPath: projectPath,
                                          context: context)
        } else {
            throw BuildFileError.invalidBuildFileType(type)
        }
    }

    /// Returns true if the two instances of BaseResourcesBuildFile are equal.
    ///
    /// - Parameters:
    ///   - lhs: first instance to be compared.
    ///   - rhs: second instance to be compared.
    /// - Returns: true if the two instances are the same.
    static func == (_: BaseResourcesBuildFile, _: BaseResourcesBuildFile) -> Bool {
        return true
    }
}

/// Resources build phase.
class ResourcesBuildFile: BaseResourcesBuildFile, GraphJSONInitiatable {
    /// Paths.
    let paths: [AbsolutePath]

    /// Initializes the resources build file with its attributes.
    ///
    /// - Parameter paths: paths.
    init(_ paths: [AbsolutePath] = []) {
        self.paths = paths
    }

    required init(json: JSON,
                  projectPath: AbsolutePath,
                  context _: GraphLoaderContexting) throws {
        let pattern: String = try json.get("pattern")
        paths = projectPath.glob(pattern)
    }

    /// Returns true if the two instances of ResourcesBuildFile are equal.
    ///
    /// - Parameters:
    ///   - lhs: first instance to be compared.
    ///   - rhs: second instance to be compared.
    /// - Returns: true if the two instances are the same.
    static func == (lhs: ResourcesBuildFile, rhs: ResourcesBuildFile) -> Bool {
        return lhs.paths == rhs.paths
    }
}

/// Core data model build file.
class CoreDataModelBuildFile: BaseResourcesBuildFile, GraphJSONInitiatable {
    /// Relative path to the model.
    let path: AbsolutePath

    /// Core data versions paths.
    let versions: [AbsolutePath]

    /// Current version (without extension)
    let currentVersion: String

    /// Initializes the core data model build file with its attributes.
    ///
    /// - Parameters:
    ///   - path: path.
    ///   - currentVersion: current version (without extension).
    ///   - versions: paths to the versions models.
    init(_ path: AbsolutePath,
         currentVersion: String,
         versions: [AbsolutePath]) {
        self.path = path
        self.currentVersion = currentVersion
        self.versions = versions
    }

    required init(json: JSON,
                  projectPath: AbsolutePath,
                  context _: GraphLoaderContexting) throws {
        let pathString: String = try json.get("path")
        path = projectPath.appending(RelativePath(pathString))
        currentVersion = try json.get("current_version")
        versions = path.glob("*.xcdatamodel")
    }

    /// Returns true if the two instances of CoreDataModelBuildFile are equal.
    ///
    /// - Parameters:
    ///   - lhs: first instance to be compared.
    ///   - rhs: second instance to be compared.
    /// - Returns: true if the two instances are the same.
    static func == (lhs: CoreDataModelBuildFile, rhs: CoreDataModelBuildFile) -> Bool {
        return lhs.path == rhs.path &&
            lhs.currentVersion == rhs.currentVersion
    }
}

/// File that can be copied.
///
/// - product: file in the products directory.
/// - path: file
enum CopyBuildFile: GraphJSONInitiatable, Equatable {
    case product(String)
    case path(AbsolutePath)

    init(json: JSON,
         projectPath: AbsolutePath,
         context _: GraphLoaderContexting) throws {
        let type: String = try json.get("type")
        switch type {
        case "product":
            let name: String = try json.get("name")
            self = .product(name)
        case "path":
            let pathString: String = try json.get("path")
            let path = RelativePath(pathString)
            self = .path(projectPath.appending(path))
        default:
            fatalError("Invalid copiable file type")
        }
    }

    /// Returns true if the two instances of CopyBuildFile are equal.
    ///
    /// - Parameters:
    ///   - lhs: first instance to be compared.
    ///   - rhs: second instance to be compared.
    /// - Returns: true if the two instances are the same.
    static func == (lhs: CopyBuildFile, rhs: CopyBuildFile) -> Bool {
        switch (lhs, rhs) {
        case let (.product(lhsName), .product(rhsName)):
            return lhsName == rhsName
        case let (.path(lhsPath), .path(rhsPath)):
            return lhsPath == rhsPath
        default:
            return false
        }
    }
}

/// Headers build file.
class HeadersBuildFile: GraphJSONInitiatable, Equatable {
    /// Header access level.
    ///
    /// - private: private.
    /// - public: public.
    /// - project: project.
    enum AccessLevel: String {
        case `private`, `public`, project
    }

    /// Paths.
    let paths: [AbsolutePath]

    /// Access level.
    let accessLevel: AccessLevel

    /// Initializes the headers build file with its attributes.
    ///
    /// - Parameters:
    ///   - paths: paths.
    ///   - accessLevel: access level.
    init(_ paths: [AbsolutePath],
         accessLevel: AccessLevel) {
        self.paths = paths
        self.accessLevel = accessLevel
    }

    required init(json: JSON,
                  projectPath: AbsolutePath,
                  context _: GraphLoaderContexting) throws {
        let pattern: String = try json.get("pattern")
        paths = projectPath.glob(pattern)
        let accessLevelString: String = try json.get("access_level")
        accessLevel = AccessLevel(rawValue: accessLevelString)!
    }

    /// Returns true if the two instances of HeadersBuildFile are equal.
    ///
    /// - Parameters:
    ///   - lhs: first instance to be compared.
    ///   - rhs: second instance to be compared.
    /// - Returns: true if the two instances are the same.
    static func == (lhs: HeadersBuildFile, rhs: HeadersBuildFile) -> Bool {
        return lhs.paths == rhs.paths &&
            lhs.accessLevel == rhs.accessLevel
    }
}
