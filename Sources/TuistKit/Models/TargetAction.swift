import Basic
import Foundation
import TuistCore

/// It represents a target script build phase
public struct TargetAction {
    /// Order when the action gets executed.
    ///
    /// - pre: Before the sources and resources build phase.
    /// - post: After the sources and resources build phase.
    enum Order: String {
        case pre
        case post
    }

    /// Name of the build phase when the project gets generated
    let name: String

    /// Name of the tool to execute. Tuist will look up the tool on the environment's PATH
    let tool: String?

    /// Path to the script to execute
    let path: AbsolutePath?

    /// Target action order
    let order: Order

    /// Arguments that to be passed
    let arguments: [String]

    /// Initializes a new target action with its attributes.
    ///
    /// - Parameters:
    ///   - name: Name of the build phase when the project gets generated
    ///   - order: Target action order
    ///   - tool: Name of the tool to execute. Tuist will look up the tool on the environment's PATH
    ///   - path: Path to the script to execute
    ///   - arguments: Arguments that to be passed
    init(name: String,
         order: Order,
         tool: String? = nil,
         path: AbsolutePath? = nil,
         arguments: [String] = []) {
        self.name = name
        self.order = order
        self.tool = tool
        self.path = path
        self.arguments = arguments
    }

    /// Returns the shell script that should be used in the target build phase.
    ///
    /// - Parameters:
    ///   - sourceRootPath: Path to the directory where the Xcode project is generated.
    ///   - system: System instance used to obtain the absolute path of the tool.
    /// - Returns: Shell script that should be used in the target build phase.
    /// - Throws: An error if the tool absolute path cannot be obtained.
    func shellScript(sourceRootPath: AbsolutePath,
                     system: Systeming = System()) throws -> String {
        if let path = path {
            return "\(path.relative(to: sourceRootPath).asString) \(arguments.joined(separator: " "))"
        } else {
            return try "\(system.which(tool!).spm_chomp().spm_chuzzle()!) \(arguments.joined(separator: " "))"
        }
    }
}

extension Array where Element == TargetAction {
    var preActions: [TargetAction] {
        return filter({ $0.order == .pre })
    }

    var postActions: [TargetAction] {
        return filter({ $0.order == .post })
    }
}
