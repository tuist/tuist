import Basic
import Foundation

class BuildPhase: Equatable {
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

    static func == (_: BuildPhase, _: BuildPhase) -> Bool {
        return true
    }
}

/// Sources build phase
class SourcesBuildPhase: BuildPhase, GraphJSONInitiatable {
    /// Build files.
    let buildFiles: [SourcesBuildFile]

    /// Initializes the sources build phase with its build files.
    ///
    /// - Parameter buildFiles: build files.
    init(buildFiles: [SourcesBuildFile] = []) {
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
        let files: [JSON] = try json.get("files")
        buildFiles = try files.map({ try SourcesBuildFile(json: $0, projectPath: projectPath, context: context) })
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

/// Resources build phase.
class ResourcesBuildPhase: BuildPhase, GraphJSONInitiatable {
    /// Build files.
    let buildFiles: [BaseResourcesBuildFile]

    /// Initializes the resources build phase with its build files.
    ///
    /// - Parameter buildFiles: build files.
    init(buildFiles: [BaseResourcesBuildFile] = []) {
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
        let files: [JSON] = try json.get("files")
        buildFiles = try files.map({ try ResourcesBuildFile.from(json: $0,
                                                                 projectPath: projectPath,
                                                                 context: context) })
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

    /// Build phase name.
    let name: String

    /// Destination.
    let destination: Destination

    /// Subpath.
    let subpath: String?

    /// True if resources should be copied only when installing.
    let copyWhenInstalling: Bool

    /// Initializes the build phase with its attributes.
    ///
    /// - Parameters:
    ///   - name: build phase name.
    ///   - destination: build phase destination.
    ///   - subpath: sub-path inside destination.
    ///   - copyWhenInstalling: true if resources should be copied only when installing.
    init(name: String,
         destination: Destination,
         subpath: String? = nil,
         copyWhenInstalling: Bool = true) {
        self.name = name
        self.destination = destination
        self.subpath = subpath
        self.copyWhenInstalling = copyWhenInstalling
    }

    /// Initializes the build phase from its JSON representation.
    ///
    /// - Parameter json: JSON representation.
    /// - Throws: an error if the build phase cannot be parsed from the JSON.
    init(json: JSON) throws {
        name = try json.get("name")
        let destinationString: String = try json.get("destination")
        destination = Destination(rawValue: destinationString)!
        subpath = try? json.get("subpath")
        copyWhenInstalling = try json.get("copy_when_installing")
    }

    /// Compares copy files build phases.
    ///
    /// - Parameters:
    ///   - lhs: first build phase to compare.
    ///   - rhs: second build phase to compare.
    /// - Returns: true if the two build phases are the same
    static func == (lhs: CopyBuildPhase, rhs: CopyBuildPhase) -> Bool {
        return lhs.name == rhs.name &&
            lhs.destination == rhs.destination &&
            lhs.subpath == rhs.subpath &&
            lhs.copyWhenInstalling == rhs.copyWhenInstalling
    }
}

/// Script build phase.
class ScriptBuildPhase: BuildPhase {
    /// Build phase name.
    let name: String

    /// Shell used to run the script.
    let shell: String

    /// Script  to be executed.
    let script: String

    /// Input files.
    let inputFiles: [String]

    /// Output files.
    let outputFiles: [String]

    /// Initialies the build phase with its properties.
    ///
    /// - Parameters:
    ///   - name: build phase name.
    ///   - shell: shell used to run the script.
    ///   - script: script to be  run.
    ///   - inputFiles: input files.
    ///   - outputFiles: output files.
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

    /// Initializes the build phase from its JSON representation.
    ///
    /// - Parameter json: JSON representation.
    /// - Throws: an error if the build phase cannot be parsed from the JSON.
    init(json: JSON) throws {
        name = try json.get("name")
        shell = try json.get("shell")
        script = try json.get("script")
        inputFiles = try json.get("input_files")
        outputFiles = try json.get("output_files")
    }

    /// Compares two script build phases.
    ///
    /// - Parameters:
    ///   - lhs: first build phase to be compared.
    ///   - rhs: second build  phase to be compared.
    /// - Returns: true if the two build phases are the same.
    static func == (lhs: ScriptBuildPhase, rhs: ScriptBuildPhase) -> Bool {
        return lhs.name == rhs.name &&
            lhs.shell == rhs.name &&
            lhs.script == rhs.script &&
            lhs.inputFiles == rhs.inputFiles &&
            lhs.outputFiles == rhs.outputFiles
    }
}

/// Headers build phase.
class HeadersBuildPhase: BuildPhase, GraphJSONInitiatable {
    /// Build files.
    let buildFiles: [HeadersBuildFile]

    /// Initializes the build phase with its attributes.
    ///
    /// - Parameter buildFiles: build files.
    init(buildFiles: [HeadersBuildFile] = []) {
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
        let files: [JSON] = try json.get("files")
        buildFiles = try files.map({ try HeadersBuildFile(json: $0, projectPath: projectPath, context: context) })
    }

    /// Compares two headers build phases.
    ///
    /// - Parameters:
    ///   - lhs: first build phase to be compared.
    ///   - rhs: second build  phase to be compared.
    /// - Returns: true if the two build phases are the same.
    static func == (lhs: HeadersBuildPhase, rhs: HeadersBuildPhase) -> Bool {
        return lhs.buildFiles == rhs.buildFiles
    }
}
