import Foundation
import TSCBasic

/// It represents a target script build phase
public struct TargetScript: Equatable, Codable {
    /// Order when the script gets executed.
    ///
    /// - pre: Before the sources and resources build phase.
    /// - post: After the sources and resources build phase.
    public enum Order: String, Equatable, Codable {
        case pre
        case post
    }

    /// Specifies how to execute the target script
    ///
    /// - tool: Executes the tool with the given arguments. Tuist will look up the tool on the environment's PATH.
    /// - scriptPath: Executes the file at the path with the given arguments.
    /// - embedded: Executes the embedded script. This should be a short command.
    public enum Script: Equatable, Codable {
        case tool(path: String, args: [String] = [])
        case scriptPath(path: AbsolutePath, args: [String] = [])
        case embedded(String)
    }

    /// Name of the build phase when the project gets generated
    public let name: String

    /// The script to execute in the script
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

    /// Target script order
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
    public let runForInstallBuildsOnly: Bool

    /// The path to the shell which shall execute this script.
    public let shellPath: String

    /// The path to the dependency file
    public let dependencyFile: AbsolutePath?

    /// Initializes a new target script with its attributes using a script at the given path to be executed.
    ///
    /// - Parameters:
    ///   - name: Name of the build phase when the project gets generated
    ///   - order: Target script order
    ///   - script: The script to execute in the script
    ///   - inputPaths: List of input file paths
    ///   - inputFileListPaths: List of input filelist paths
    ///   - outputPaths: List of output file paths
    ///   - outputFileListPaths: List of output filelist paths
    ///   - showEnvVarsInLog: Show environment variables in the logs
    ///   - basedOnDependencyAnalysis: Whether to skip running this script in incremental builds
    ///   - runForInstallBuildsOnly: Whether this script only runs on install builds (default is false)
    ///   - shellPath: The path to the shell which shall execute this script. Default is `/bin/sh`.
    ///   - dependencyFile The path to the dependency file. Default is `nil`.
    public init(
        name: String,
        order: Order,
        script: Script = .embedded(""),
        inputPaths: [AbsolutePath] = [],
        inputFileListPaths: [AbsolutePath] = [],
        outputPaths: [AbsolutePath] = [],
        outputFileListPaths: [AbsolutePath] = [],
        showEnvVarsInLog: Bool = true,
        basedOnDependencyAnalysis: Bool? = nil,
        runForInstallBuildsOnly: Bool = false,
        shellPath: String = "/bin/sh",
        dependencyFile: AbsolutePath? = nil
    ) {
        self.name = name
        self.order = order
        self.script = script
        self.inputPaths = inputPaths
        self.inputFileListPaths = inputFileListPaths
        self.outputPaths = outputPaths
        self.outputFileListPaths = outputFileListPaths
        self.showEnvVarsInLog = showEnvVarsInLog
        self.basedOnDependencyAnalysis = basedOnDependencyAnalysis
        self.runForInstallBuildsOnly = runForInstallBuildsOnly
        self.shellPath = shellPath
        self.dependencyFile = dependencyFile
    }
}

extension Array where Element == TargetScript {
    public var preScripts: [TargetScript] {
        filter { $0.order == .pre }
    }

    public var postScripts: [TargetScript] {
        filter { $0.order == .post }
    }
}
