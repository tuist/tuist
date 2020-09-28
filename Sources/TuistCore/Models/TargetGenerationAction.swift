import Foundation
import TSCBasic
import TuistSupport

/// It represents an action to be called at a determined point in the generation
public struct TargetGenerationAction: Codable, Equatable {
    /// Order when the project generation action gets called.
    ///
    /// - pre: Before the target is generated.
    /// - post: After the target is generated.
    public enum Order: String, Codable, Equatable {
        case pre
        case post
    }

    /// Name of the tool to execute. Tuist will look up the tool on the environment's PATH
    public let tool: String?

    /// Path to the script to execute
    public let path: AbsolutePath?

    /// Target generation action order.
    public let order: Order

    /// Arguments that to be passed
    public let arguments: [String]

    /// Initializes a new target action with its attributes.
    ///
    /// - Parameters:
    ///   - order: Target generation action order.
    ///   - tool: Name of the tool to execute. Tuist will look up the tool on the environment's PATH
    ///   - path: Path to the script to execute
    ///   - arguments: Arguments that to be passed
    public init(order: Order,
                tool: String? = nil,
                path: AbsolutePath? = nil,
                arguments: [String] = [])
    {
        self.order = order
        self.tool = tool
        self.path = path
        self.arguments = arguments
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

extension Array where Element == TargetGenerationAction {
    public var preActions: [TargetGenerationAction] {
        filter { $0.order == .pre }
    }

    public var postActions: [TargetGenerationAction] {
        filter { $0.order == .post }
    }
}
