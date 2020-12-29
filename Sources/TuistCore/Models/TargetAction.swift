import Foundation
import TSCBasic
import TuistSupport

/// It represents a target script build phase
public struct TargetAction: Equatable {
    /// Order when the action gets executed.
    ///
    /// - pre: Before the sources and resources build phase.
    /// - post: After the sources and resources build phase.
    public enum Order: String, Equatable {
        case pre
        case post
    }

    /// Specifies how to execute the target action
    ///
    /// - tool: Executes the tool with the given arguments. Tuist will look up the tool on the environment's PATH.
    /// - scriptPath: Executes the file at the path with the given arguments.
    /// - text: Executes the embedded script. This should be a short command.
    public enum Script: Equatable {
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
    public init(name: String,
                order: Order,
                script: Script = .embedded(""),
                inputPaths: [AbsolutePath] = [],
                inputFileListPaths: [AbsolutePath] = [],
                outputPaths: [AbsolutePath] = [],
                outputFileListPaths: [AbsolutePath] = [],
                showEnvVarsInLog: Bool = true,
                basedOnDependencyAnalysis: Bool? = nil)
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
    }

    /// Returns the shell script that should be used in the target build phase.
    ///
    /// - Parameters:
    ///   - sourceRootPath: Path to the directory where the Xcode project is generated.
    /// - Returns: Shell script that should be used in the target build phase.
    /// - Throws: An error if the tool absolute path cannot be obtained.
    public func shellScript(sourceRootPath: AbsolutePath) throws -> String {
        switch script {
        case let .embedded(text):
            return text.spm_chomp().spm_chuzzle() ?? ""

        case let .scriptPath(path, args: args):
            return "\"${PROJECT_DIR}\"/\(path.relative(to: sourceRootPath).pathString) \(args.joined(separator: " "))"

        case let .tool(tool, args):
            return try "\(System.shared.which(tool).spm_chomp().spm_chuzzle()!) \(args.joined(separator: " "))"
        }
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
