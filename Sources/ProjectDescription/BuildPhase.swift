import Foundation

public class BuildPhase {
    public static func sources(_ files: [SourcesBuildFile] = []) -> BuildPhase {
        return SourcesBuildPhase(files: files)
    }

    public static func resources(_ files: [ResourcesBuildFile] = []) -> BuildPhase {
        return ResourcesBuildPhase(files: files)
    }

    public static func copy(name: String,
                            destination: CopyBuildPhase.Destination,
                            files: [CopyBuildFile],
                            subpath: String? = nil,
                            copyWhenInstalling: Bool = true) -> CopyBuildPhase {
        return CopyBuildPhase(name: name,
                              destination: destination,
                              files: files,
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

    public static func headers(_ files: [HeadersBuildFile]) -> HeadersBuildPhase {
        return HeadersBuildPhase(files: files)
    }
}

// MARK: - SourcesBuildPhase

public class SourcesBuildPhase: BuildPhase {
    public let files: [SourcesBuildFile]
    public init(files: [SourcesBuildFile] = []) {
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
    public let files: [ResourcesBuildFile]
    public init(files: [ResourcesBuildFile] = []) {
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
        case absolutePath
        case productsDirectory
        case wrapper
        case resources
        case executables
        case javaResources
        case frameworks
        case sharedFrameworks
        case sharedSupport
        case plugins

        func toJSON() -> JSON {
            return .string(rawValue)
        }
    }

    public let name: String
    public let destination: Destination
    public let files: [CopyBuildFile]
    public let subpath: String?
    public let copyWhenInstalling: Bool

    public init(name: String,
                destination: Destination,
                files: [CopyBuildFile],
                subpath: String? = nil,
                copyWhenInstalling: Bool = true) {
        self.name = name
        self.destination = destination
        self.files = files
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
        dictionary["files"] = JSON.array(files.map({ $0.toJSON() }))
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
    public let files: [HeadersBuildFile]

    public init(files: [HeadersBuildFile] = []) {
        self.files = files
    }
}

// MARK: - HeadersBuildPhase (JSONConvertible)

extension HeadersBuildPhase: JSONConvertible {
    func toJSON() -> JSON {
        var dictionary: [String: JSON] = [:]
        dictionary["type"] = "headers".toJSON()
        dictionary["files"] = files.toJSON()
        return .dictionary(dictionary)
    }
}
