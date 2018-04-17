import Foundation
import Basic

// MARK: - BuildPhase

class BuildPhase {
    static func from(json: JSON, context: GraphLoaderContexting) throws -> BuildPhase {
        let type: String = try json.get("type")
        if type == "sources" {
            return try SourcesBuildPhase(json: json, context: context)
        } else if type == "resources" {
            return try ResourcesBuildPhase(json: json, context: context)
        } else if type == "copy" {
            return try CopyBuildPhase(json: json)
        } else if type == "script" {
            return try ScriptBuildPhase(json: json)
        } else if type == "headers" {
            return try HeadersBuildPhase(json: json, context: context)
        } else {
            fatalError()
        }
    }
}

// MARK: - SourcesBuildPhase

class SourcesBuildPhase: BuildPhase {
    let files: Set<AbsolutePath>

    init(files: Set<AbsolutePath> = Set()) {
        self.files = files
    }

    required init(json: JSON, context: GraphLoaderContexting) throws {
        let buildFiles: [BuildFiles] = try json.get("files")
        self.files = buildFiles.list(context: context)
    }
}

extension SourcesBuildPhase: Equatable {
    static func ==(lhs: SourcesBuildPhase, rhs: SourcesBuildPhase) -> Bool {
        return lhs.files == rhs.files
    }
}

// MARK: - ResourcesBuildPhase

class ResourcesBuildPhase: BuildPhase {
    let files: Set<AbsolutePath>

    init(files: Set<AbsolutePath> = Set()) {
        self.files = files
    }

    required init(json: JSON, context: GraphLoaderContexting) throws {
        let buildFiles: [BuildFiles] = try json.get("files")
        self.files = buildFiles.list(context: context)
    }
}

extension ResourcesBuildPhase: Equatable {
    static func ==(lhs: ResourcesBuildPhase, rhs: ResourcesBuildPhase) -> Bool {
        return lhs.files == rhs.files
    }
}

// MARK: - CopyBuildPhase

class CopyBuildPhase: BuildPhase {
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
    let `public`: Set<AbsolutePath>
    let project: Set<AbsolutePath>
    let `private`: Set<AbsolutePath>

    init(public: Set<AbsolutePath> = Set(),
         project: Set<AbsolutePath> = Set(),
         private: Set<AbsolutePath> = Set()) {
        self.public = `public`
        self.project = project
        self.private = `private`
    }

    init(json: JSON, context: GraphLoaderContexting) throws {
        let publicBuildFiles: [BuildFiles] = try json.get("public")
        `public` = publicBuildFiles.list(context: context)
        let projectBuildFiles: [BuildFiles] = try json.get("project")
        project = projectBuildFiles.list(context: context)
        let privateBuildfiles: [BuildFiles] = try json.get("private")
        `private` = privateBuildfiles.list(context: context)
    }
}
