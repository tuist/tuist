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
    private let name: String

    /// Name of the tool to execute. Tuist will look up the tool on the environment's PATH.
    private let tool: String?

    /// Path to the script to execute.
    private let path: String?

    /// Target action order.
    private let order: Order

    /// Arguments that to be passed.
    private let arguments: [String]

    // MARK: - GraphJSONInitiatable

    init(json: JSON, projectPath _: AbsolutePath, fileHandler _: FileHandling) throws {
        name = try json.get("name")
        order = Order(rawValue: try json.get("order"))!
        arguments = try json.get("arguments")
        path = try? json.get("path")
        tool = try? json.get("name")
    }
}
