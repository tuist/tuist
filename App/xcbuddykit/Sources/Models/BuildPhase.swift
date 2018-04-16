import Foundation
import PathKit
import Unbox

// MARK: - BuildPhase

class BuildPhase {
    static func from(unboxer: Unboxer, context: GraphLoaderContexting) throws -> BuildPhase {
        let type: String = try unboxer.unbox(key: "type")
        if type == "sources" {
            return try SourcesBuildPhase(unboxer: unboxer, context: context)
        } else if type == "resources" {
            return try ResourcesBuildPhase(unboxer: unboxer, context: context)
        } else if type == "copy" {
            return try CopyBuildPhase(unboxer: unboxer)
        } else if type == "script" {
            return try ScriptBuildPhase(unboxer: unboxer)
        } else if type == "headers" {
            return try HeadersBuildPhase(unboxer: unboxer)
        } else {
            fatalError()
        }
    }
}

// MARK: - SourcesBuildPhase

class SourcesBuildPhase: BuildPhase {
    let files: Set<Path>

    init(files: Set<Path> = Set()) {
        self.files = files
    }

    required init(unboxer: Unboxer, context: GraphLoaderContexting) throws {
        let buildFiles: [BuildFiles] = try unboxer.unbox(key: "files")
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
    let files: Set<Path>

    init(files: Set<Path> = Set()) {
        self.files = files
    }

    required init(unboxer: Unboxer, context: GraphLoaderContexting) throws {
        let buildFiles: [BuildFiles] = try unboxer.unbox(key: "files")
        self.files = buildFiles.list(context: context)
    }
}

extension ResourcesBuildPhase: Equatable {
    static func ==(lhs: ResourcesBuildPhase, rhs: ResourcesBuildPhase) -> Bool {
        return lhs.files == rhs.files
    }
}

// MARK: - CopyBuildPhase

class CopyBuildPhase: BuildPhase, Unboxable {
    enum Destination: String, UnboxableEnum {
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

    required init(unboxer: Unboxer) throws {
        name = try unboxer.unbox(key: "name")
        destination = try unboxer.unbox(key: "destination")
        subpath = unboxer.unbox(key: "subpath")
        copyWhenInstalling = try unboxer.unbox(key: "copy_when_installing")
    }
}

class ScriptBuildPhase: BuildPhase, Unboxable {
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

    required init(unboxer: Unboxer) throws {
        name = try unboxer.unbox(key: "name")
        shell = try unboxer.unbox(key: "shell")
        script = try unboxer.unbox(key: "script")
        inputFiles = try unboxer.unbox(key: "input_files")
        outputFiles = try unboxer.unbox(key: "output_files")
    }
}

class HeadersBuildPhase: BuildPhase, Unboxable {
    let `public`: [BuildFiles]
    let project: [BuildFiles]
    let `private`: [BuildFiles]

    init(public: [BuildFiles] = [],
         project: [BuildFiles] = [],
         private: [BuildFiles] = []) {
        self.public = `public`
        self.project = project
        self.private = `private`
    }

    required init(unboxer: Unboxer) throws {
        `public` = try unboxer.unbox(key: "public")
        project = try unboxer.unbox(key: "project")
        `private` = try unboxer.unbox(key: "private")
    }
}
