import Foundation
import TSCBasic

/// It represents a target script build phase
public struct TargetAction: Equatable, Codable {
    /// Order when the action gets executed.
    ///
    /// - pre: Before the sources and resources build phase.
    /// - post: After the sources and resources build phase.
    public enum Order: String, Equatable, Codable {
        case pre
        case post
    }

    /// Specifies how to execute the target action
    ///
    /// - tool: Executes the tool with the given arguments. Tuist will look up the tool on the environment's PATH.
    /// - scriptPath: Executes the file at the path with the given arguments.
    /// - embedded: Executes the embedded script. This should be a short command.
    public enum Script: Equatable, Codable {
        case tool(_ path: String, _ args: [String] = [])
        case scriptPath(_ path: AbsolutePath, args: [String] = [])
        case embedded(String)
    }

    /// Name of the build phase when the project gets generated
    public let name: String

    /// The script to execute in the action
    public let script: Script

    /// The text of the embedded script
    public var embeddedScript: String? {
        if case let Script.embedded(embeddedScript) = script {
            return embeddedScript
        }

        return nil
    }

    /// Name of the tool to execute. Tuist will look up the tool on the environment's PATH.
    public var tool: String? {
        if case let Script.tool(tool, _) = script {
            return tool
        }

        return nil
    }

    /// Path to the script to execute.
    public var path: AbsolutePath? {
        if case let Script.scriptPath(path, _) = script {
            return path
        }

        return nil
    }

    /// Target action order
    public let order: Order

    /// Arguments that to be passed
    public var arguments: [String] {
        switch script {
        case let .scriptPath(_, args), let .tool(_, args):
            return args

        case .embedded:
            return []
        }
    }

    /// List of input file paths
    public let inputPaths: [AbsolutePath]

    /// List of input filelist paths
    public let inputFileListPaths: [AbsolutePath]

    /// List of output file paths
    public let outputPaths: [AbsolutePath]

    /// List of output filelist paths
    public let outputFileListPaths: [AbsolutePath]

    /// Show environment variables in the logs
    public var showEnvVarsInLog: Bool

    /// Whether to skip running this script in incremental builds, if nothing has changed
    public let basedOnDependencyAnalysis: Bool?
    
    /// Whether this script only runs on install builds (default is false)
    public let runOnlyForDeploymentPostprocessing: Bool

    /// Initializes a new target action with its attributes using a script at the given path to be executed.
    ///
    /// - Parameters:
    ///   - name: Name of the build phase when the project gets generated
    ///   - order: Target action order
    ///   - path: Path to the script to execute
    ///   - arguments: Arguments that to be passed
    ///   - inputPaths: List of input file paths
    ///   - inputFileListPaths: List of input filelist paths
    ///   - outputPaths: List of output file paths
    ///   - outputFileListPaths: List of output filelist paths
    ///   - showEnvVarsInLog: Show environment variables in the logs
    ///   - basedOnDependencyAnalysis: Whether to skip running this script in incremental builds
    ///   - runOnlyForDeploymentPostprocessing: Whether this script only runs on install builds (default is false)
    public init(name: String,
                order: Order,
                script: Script = .embedded(""),
                inputPaths: [AbsolutePath] = [],
                inputFileListPaths: [AbsolutePath] = [],
                outputPaths: [AbsolutePath] = [],
                outputFileListPaths: [AbsolutePath] = [],
                showEnvVarsInLog: Bool = true,
                basedOnDependencyAnalysis: Bool? = nil,
                runOnlyForDeploymentPostprocessing: Bool = false)
    {
        self.name = name
        self.order = order
        self.script = script
        self.inputPaths = inputPaths
        self.inputFileListPaths = inputFileListPaths
        self.outputPaths = outputPaths
        self.outputFileListPaths = outputFileListPaths
        self.showEnvVarsInLog = showEnvVarsInLog
        self.basedOnDependencyAnalysis = basedOnDependencyAnalysis
        self.runOnlyForDeploymentPostprocessing = runOnlyForDeploymentPostprocessing
    }
}

extension Array where Element == TargetAction {
    public var preActions: [TargetAction] {
        filter { $0.order == .pre }
    }

    public var postActions: [TargetAction] {
        filter { $0.order == .post }
    }
}

// MARK: - TargetAction.Script - Codable

extension TargetAction.Script {
    private enum Kind: String, Codable {
        case tool
        case scriptPath
        case embedded
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case path
        case absolutePath
        case args
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .tool:
            let path = try container.decode(String.self, forKey: .path)
            let args = try container.decode([String].self, forKey: .args)
            self = .tool(path, args)
        case .scriptPath:
            let absolutePath = try container.decode(AbsolutePath.self, forKey: .absolutePath)
            let args = try container.decode([String].self, forKey: .args)
            self = .scriptPath(absolutePath, args: args)
        case .embedded:
            let path = try container.decode(String.self, forKey: .path)
            self = .embedded(path)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .tool(path, args):
            try container.encode(Kind.tool, forKey: .kind)
            try container.encode(path, forKey: .path)
            try container.encode(args, forKey: .args)
        case let .scriptPath(absolutePath, args):
            try container.encode(Kind.scriptPath, forKey: .kind)
            try container.encode(absolutePath, forKey: .absolutePath)
            try container.encode(args, forKey: .args)
        case let .embedded(path):
            try container.encode(Kind.embedded, forKey: .kind)
            try container.encode(path, forKey: .path)
        }
    }
}
