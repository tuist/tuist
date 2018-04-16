import Foundation

public class BuildPhase {
    public static func sources(_ files: [BuildFiles] = []) -> BuildPhase {
        return SourcesBuildPhase(files: files)
    }

    public static func resources(_ files: [BuildFiles] = []) -> BuildPhase {
        return ResourcesBuildPhase(files: files)
    }

    public static func copy(name: String, destination: CopyBuildPhase.Destination, subpath: String? = nil, copyWhenInstalling: Bool = true) -> CopyBuildPhase {
        return CopyBuildPhase(name: name,
                              destination: destination,
                              subpath: subpath,
                              copyWhenInstalling: copyWhenInstalling)
    }

    public static func script(name: String,
                              shell: String = "/bin/sh",
                              script: String = "",
                              inputFiles: [String] = [],
                              outputFiles: [String] = []) -> ScriptBuildPhase {
        return ScriptBuildPhase(name: name,
                                shell: shell,
                                script: script,
                                inputFiles: inputFiles,
                                outputFiles: outputFiles)
    }

    public static func headers(public: [BuildFiles] = [],
                               project: [BuildFiles] = [],
                               private: [BuildFiles] = []) -> HeadersBuildPhase {
        return HeadersBuildPhase(public: `public`, project: project, private: `private`)
    }
}

// MARK: - SourcesBuildPhase

public class SourcesBuildPhase: BuildPhase {
    public let files: [BuildFiles]
    public init(files: [BuildFiles] = []) {
        self.files = files
    }
}

// MARK: - SourcesBuildPhase (JSONConvertible)

extension SourcesBuildPhase: JSONConvertible {
    func toJSON() -> JSON {
        return .dictionary([
            "type": "sources".toJSON(),
            "files": files.toJSON(),
        ])
    }
}

// MARK: - ResourcesBuildPhase

public class ResourcesBuildPhase: BuildPhase {
    public let files: [BuildFiles]
    public init(files: [BuildFiles] = []) {
        self.files = files
    }
}

// MARK: - ResourcesBuildPhase (JSONConvertible)

extension ResourcesBuildPhase: JSONConvertible {
    func toJSON() -> JSON {
        return .dictionary([
            "type": "resources".toJSON(),
            "files": files.toJSON(),
        ])
    }
}

// MARK: - CopyBuildPhase

public class CopyBuildPhase: BuildPhase {
    public enum Destination: String {
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

        func toJSON() -> JSON {
            return .string(rawValue)
        }
    }

    public let name: String
    public let destination: Destination
    public let subpath: String?
    public let copyWhenInstalling: Bool

    public init(name: String,
                destination: Destination,
                subpath: String? = nil,
                copyWhenInstalling: Bool = true) {
        self.name = name
        self.destination = destination
        self.subpath = subpath
        self.copyWhenInstalling = copyWhenInstalling
    }
}

// MARK: - CopyBuildPhase (JSONConvertible)

extension CopyBuildPhase: JSONConvertible {
    func toJSON() -> JSON {
        var dictionary: [String: JSON] = [:]
        dictionary["type"] = "copy".toJSON()
        dictionary["name"] = name.toJSON()
        dictionary["destination"] = destination.toJSON()
        if let subpath = subpath {
            dictionary["subpath"] = subpath.toJSON()
        }
        dictionary["copy_when_installing"] = copyWhenInstalling.toJSON()
        return .dictionary(dictionary)
    }
}

// MARK: - ScriptBuildPhase

public class ScriptBuildPhase: BuildPhase {
    public let name: String
    public let shell: String // /bin/sh
    public let script: String
    public let inputFiles: [String]
    public let outputFiles: [String]

    public init(name: String,
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
}

// MARK: - ScriptBuildPhase (JSONConvertible)

extension ScriptBuildPhase: JSONConvertible {
    func toJSON() -> JSON {
        var dictionary: [String: JSON] = [:]
        dictionary["type"] = "script".toJSON()
        dictionary["name"] = name.toJSON()
        dictionary["shell"] = name.toJSON()
        dictionary["script"] = script.toJSON()
        dictionary["input_files"] = inputFiles.toJSON()
        dictionary["output_files"] = outputFiles.toJSON()
        return .dictionary(dictionary)
    }
}

// MARK: - HeadersBuildPhase

public class HeadersBuildPhase: BuildPhase {
    public let `public`: [BuildFiles]
    public let project: [BuildFiles]
    public let `private`: [BuildFiles]

    public init(public: [BuildFiles] = [],
                project: [BuildFiles] = [],
                private: [BuildFiles] = []) {
        self.public = `public`
        self.project = project
        self.private = `private`
    }
}

// MARK: - HeadersBuildPhase (JSONConvertible)

extension HeadersBuildPhase: JSONConvertible {
    func toJSON() -> JSON {
        var dictionary: [String: JSON] = [:]
        dictionary["type"] = "headers".toJSON()
        dictionary["public"] = `public`.toJSON()
        dictionary["project"] = project.toJSON()
        dictionary["private"] = `private`.toJSON()
        return .dictionary(dictionary)
    }
}
