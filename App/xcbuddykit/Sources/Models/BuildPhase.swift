import Basic
import Foundation

// MARK: - BuildPhase

class BuildPhase {
    /// Static build phase initializer that returns the right BuildPhase based on the build phase type.
    ///
    /// - Parameters:
    ///   - json: JSON representation of the build phase.
    ///   - projectPath: path to the  folder where the project manifest is.
    ///   - context: graph loader context.
    /// - Returns: initialized build phase.
    /// - Throws: an error if the build phase cannot be parsed.
    static func parse(from json: JSON, projectPath: AbsolutePath, context: GraphLoaderContexting) throws -> BuildPhase {
        let type: String = try json.get("type")
        if type == "sources" {
            return try SourcesBuildPhase(json: json, projectPath: projectPath, context: context)
        } else if type == "resources" {
            return try ResourcesBuildPhase(json: json, projectPath: projectPath, context: context)
        } else if type == "copy" {
            return try CopyBuildPhase(json: json)
        } else if type == "script" {
            return try ScriptBuildPhase(json: json)
        } else if type == "headers" {
            return try HeadersBuildPhase(json: json, projectPath: projectPath, context: context)
        } else {
            fatalError()
        }
    }
}

// MARK: - SourcesBuildPhase

/// Sources build phase
class SourcesBuildPhase: BuildPhase, GraphJSONInitiatable, Equatable {
    /// Build files.
    let buildFiles: BuildFiles

    /// Initializes the sources build phase with its build files.
    ///
    /// - Parameter buildFiles: build files.
    init(buildFiles: BuildFiles = BuildFiles()) {
        self.buildFiles = buildFiles
    }

    /// Initializes the build phase from its JSON representation.
    ///
    /// - Parameters:
    ///   - json: target JSON representation.
    ///   - projectPath: path to the folder that contains the project's manifest.
    ///   - context: graph loader  context.
    /// - Throws: an error if build files cannot be parsed.
    required init(json: JSON, projectPath: AbsolutePath, context: GraphLoaderContexting) throws {
        buildFiles = try BuildFiles(json: json.get("files"), projectPath: projectPath, context: context)
    }

    /// Compares two sources build phases.
    ///
    /// - Parameters:
    ///   - lhs: first sources build phase.
    ///   - rhs: second sources build phase.
    /// - Returns: true if the two build phases are the same.
    static func == (lhs: SourcesBuildPhase, rhs: SourcesBuildPhase) -> Bool {
        return lhs.buildFiles == rhs.buildFiles
    }
}

// MARK: - ResourcesBuildPhase

/// Resources build phase.
class ResourcesBuildPhase: BuildPhase, GraphJSONInitiatable, Equatable {
    /// Build files.
    let buildFiles: BuildFiles

    /// Initializes the resources build phase with its build files.
    ///
    /// - Parameter buildFiles: build files.
    init(buildFiles: BuildFiles = BuildFiles()) {
        self.buildFiles = buildFiles
    }

    /// Initializes the build phase from its JSON representation.
    ///
    /// - Parameters:
    ///   - json: target JSON representation.
    ///   - projectPath: path to the folder that contains the project's manifest.
    ///   - context: graph loader  context.
    /// - Throws: an error if build files cannot be parsed.
    required init(json: JSON, projectPath: AbsolutePath, context: GraphLoaderContexting) throws {
        buildFiles = try BuildFiles(json: json.get("files"), projectPath: projectPath, context: context)
    }

    /// Compares two resources build phases.
    ///
    /// - Parameters:
    ///   - lhs: first resources build phase.
    ///   - rhs: second resources build phase.
    /// - Returns: true if the two build phases are the same.
    static func == (lhs: ResourcesBuildPhase, rhs: ResourcesBuildPhase) -> Bool {
        return lhs.buildFiles == rhs.buildFiles
    }
}

// MARK: - CopyBuildPhase

/// Copy files build phase.
class CopyBuildPhase: BuildPhase {
    /// Destination where the files from the build phase get copied.
    ///
    /// - absolutePath: absolute path  to the dest
    /// - productsDirectory: products directory.
    /// - wrapper: wrapper directory.
    /// - resources: resources directory.
    /// - executables: executables directory.
    /// - javaResources: java resources directory.
    /// - frameworks: frameworks directory.
    /// - sharedFrameworks: shared frameworks directory.
    /// - sharedSupport: shared support directory.
    /// - plugins: plugins directory.
    enum Destination: String {
        case absolutePath = "absolute_path"
        case productsDirectory = "products_directory"
        case wrapper
        case resources
        case executables
        case javaResources = "java_resources"
        case frameworks
        case sharedFrameworks = "shared_frameworks"
        case sharedSupport = "shared_support"
        case plugins = "plug_ins"
    }

    let name: String
    let destination: Destination
    let subpath: String?
    let copyWhenInstalling: Bool

    init(name: String,
         destination: Destination,
         subpath: String? = nil,
         copyWhenInstalling: Bool = true) {
        self.name = name
        self.destination = destination
        self.subpath = subpath
        self.copyWhenInstalling = copyWhenInstalling
    }

    init(json: JSON) throws {
        name = try json.get("name")
        let destinationString: String = try json.get("destination")
        destination = Destination(rawValue: destinationString)!
        subpath = json.get("subpath")
        copyWhenInstalling = try json.get("copy_when_installing")
    }
}

class ScriptBuildPhase: BuildPhase {
    let name: String
    let shell: String
    let script: String
    let inputFiles: [String]
    let outputFiles: [String]

    init(name: String,
         shell: String = "/bin/sh",
         script: String = "",
         inputFiles: [String] = [],
         outputFiles: [String] = []) {
        self.name = name
        self.shell = shell
        self.script = script
        self.inputFiles = inputFiles
        self.outputFiles = outputFiles
    }

    init(json: JSON) throws {
        name = try json.get("name")
        shell = try json.get("shell")
        script = try json.get("script")
        inputFiles = try json.get("input_files")
        outputFiles = try json.get("output_files")
    }
}

class HeadersBuildPhase: BuildPhase {
    let `public`: BuildFiles
    let project: BuildFiles
    let `private`: BuildFiles

    init(public: BuildFiles = BuildFiles(),
         project: BuildFiles = BuildFiles(),
         private: BuildFiles = BuildFiles()) {
        self.public = `public`
        self.project = project
        self.private = `private`
    }

    init(json: JSON, projectPath: AbsolutePath, context: GraphLoaderContexting) throws {
        `public` = try BuildFiles(json: json.get("public"), projectPath: projectPath, context: context)
        project = try BuildFiles(json: json.get("project"), projectPath: projectPath, context: context)
        `private` = try BuildFiles(json: json.get("private"), projectPath: projectPath, context: context)
    }
}
