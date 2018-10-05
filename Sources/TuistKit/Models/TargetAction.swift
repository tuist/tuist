import Basic
import Foundation
import TuistCore

/// It represents a target script build phase
public struct TargetAction: GraphJSONInitiatable {
    /// Order when the action gets executed.
    ///
    /// - pre: Before the sources and resources build phase.
    /// - post: After the sources and resources build phase.
    enum Order: String {
        case pre
        case post
    }

    /// Name of the build phase when the project gets generated.
    let name: String

    /// Name of the tool to execute. Tuist will look up the tool on the environment's PATH.
    let tool: String?

    /// Path to the script to execute.
    let path: AbsolutePath?

    /// Target action order.
    let order: Order

    /// Arguments that to be passed.
    let arguments: [String]

    // MARK: - GraphJSONInitiatable

    init(json: JSON, projectPath: AbsolutePath, fileHandler _: FileHandling) throws {
        name = try json.get("name")
        order = Order(rawValue: try json.get("order"))!
        arguments = try json.get("arguments")
        if let path: String = try? json.get("path") {
            self.path = AbsolutePath(path, relativeTo: projectPath)
        } else {
            path = nil
        }
        tool = try? json.get("name")
    }
}
