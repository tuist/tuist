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

    /// Name of the build phase when the project gets generated
    public let name: String

    /// Name of the tool to execute. Tuist will look up the tool on the environment's PATH
    public let tool: String?

    /// Path to the script to execute
    public let path: AbsolutePath?

    /// Target action order
    public let order: Order

    /// Arguments that to be passed
    public let arguments: [String]

    /// List of input file paths
    public let inputPaths: [AbsolutePath]

    /// List of input filelist paths
    public let inputFileListPaths: [AbsolutePath]

    /// List of output file paths
    public let outputPaths: [AbsolutePath]

    /// List of output filelist paths
    public let outputFileListPaths: [AbsolutePath]

    /// Initializes a new target action with its attributes.
    ///
    /// - Parameters:
    ///   - name: Name of the build phase when the project gets generated
    ///   - order: Target action order
    ///   - tool: Name of the tool to execute. Tuist will look up the tool on the environment's PATH
    ///   - path: Path to the script to execute
    ///   - arguments: Arguments that to be passed
    ///   - inputPaths: List of input file paths
    ///   - inputFileListPaths: List of input filelist paths
    ///   - outputPaths: List of output file paths
    ///   - outputFileListPaths: List of output filelist paths
    public init(name: String,
                order: Order,
                tool: String? = nil,
                path: AbsolutePath? = nil,
                arguments: [String] = [],
                inputPaths: [AbsolutePath] = [],
                inputFileListPaths: [AbsolutePath] = [],
                outputPaths: [AbsolutePath] = [],
                outputFileListPaths: [AbsolutePath] = [])
    {
        self.name = name
        self.order = order
        self.tool = tool
        self.path = path
        self.arguments = arguments
        self.inputPaths = inputPaths
        self.inputFileListPaths = inputFileListPaths
        self.outputPaths = outputPaths
        self.outputFileListPaths = outputFileListPaths
    }

    /// Returns the shell script that should be used in the target build phase.
    ///
    /// - Parameters:
    ///   - sourceRootPath: Path to the directory where the Xcode project is generated.
    /// - Returns: Shell script that should be used in the target build phase.
    /// - Throws: An error if the tool absolute path cannot be obtained.
    public func shellScript(sourceRootPath: AbsolutePath) throws -> String {
        if let path = path {
            return "\"${PROJECT_DIR}\"/\(path.relative(to: sourceRootPath).pathString) \(arguments.joined(separator: " "))"
        } else {
            return try "\(System.shared.which(tool!).spm_chomp().spm_chuzzle()!) \(arguments.joined(separator: " "))"
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
