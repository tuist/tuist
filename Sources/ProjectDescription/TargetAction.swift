import Foundation

public struct TargetAction: Codable {
    /// Order when the action gets executed.
    ///
    /// - pre: Before the sources and resources build phase.
    /// - post: After the sources and resources build phase.
    public enum Order: String, Codable {
        case pre
        case post
    }

    /// Name of the build phase when the project gets generated.
    public let name: String

    /// Name of the tool to execute. Tuist will look up the tool on the environment's PATH.
    public let tool: String?

    /// Path to the script to execute.
    public let path: String?

    /// Target action order.
    public let order: Order

    /// Arguments that to be passed.
    public let arguments: [String]

    public enum CodingKeys: String, CodingKey {
        case name
        case tool
        case path
        case order
        case arguments
    }

    /// Initializes the target action with its attributes.
    ///
    /// - Parameters:
    ///   - name: Name of the build phase when the project gets generated.
    ///   - tool: Name of the tool to execute. Tuist will look up the tool on the environment's PATH.
    ///   - path: Path to the script to execute.
    ///   - order: Target action order.
    ///   - arguments: Arguments that to be passed.
    init(name: String, tool: String?, path: String?, order: Order, arguments: [String]) {
        self.name = name
        self.path = path
        self.tool = tool
        self.order = order
        self.arguments = arguments
    }

    /// Returns a target action that gets executed before the sources and resources build phase.
    ///
    /// - Parameters:
    ///   - tool: Name of the tool to execute. Tuist will look up the tool on the environment's PATH.
    ///   - arguments: Arguments that to be passed.
    ///   - name: Name of the build phase when the project gets generated.
    /// - Returns: Target action.
    public static func pre(tool: String, arguments: String..., name: String) -> TargetAction {
        return TargetAction(name: name, tool: tool, path: nil, order: .pre, arguments: arguments)
    }

    /// Returns a target action that gets executed before the sources and resources build phase.
    ///
    /// - Parameters:
    ///   - tool: Name of the tool to execute. Tuist will look up the tool on the environment's PATH.
    ///   - arguments: Arguments that to be passed.
    ///   - name: Name of the build phase when the project gets generated.
    /// - Returns: Target action.
    public static func pre(tool: String, arguments: [String], name: String) -> TargetAction {
        return TargetAction(name: name, tool: tool, path: nil, order: .pre, arguments: arguments)
    }

    /// Returns a target action that gets executed before the sources and resources build phase.
    ///
    /// - Parameters:
    ///   - path: Path to the script to execute.
    ///   - arguments: Arguments that to be passed.
    ///   - name: Name of the build phase when the project gets generated.
    /// - Returns: Target action.
    public static func pre(path: String, arguments: String..., name: String) -> TargetAction {
        return TargetAction(name: name, tool: nil, path: path, order: .pre, arguments: arguments)
    }

    /// Returns a target action that gets executed before the sources and resources build phase.
    ///
    /// - Parameters:
    ///   - path: Path to the script to execute.
    ///   - arguments: Arguments that to be passed.
    ///   - name: Name of the build phase when the project gets generated.
    /// - Returns: Target action.
    public static func pre(path: String, arguments: [String], name: String) -> TargetAction {
        return TargetAction(name: name, tool: nil, path: path, order: .pre, arguments: arguments)
    }

    /// Returns a target action that gets executed after the sources and resources build phase.
    ///
    /// - Parameters:
    ///   - tool: Name of the tool to execute. Tuist will look up the tool on the environment's PATH.
    ///   - arguments: Arguments that to be passed.
    ///   - name: Name of the build phase when the project gets generated.
    /// - Returns: Target action.
    public static func post(tool: String, arguments: String..., name: String) -> TargetAction {
        return TargetAction(name: name, tool: tool, path: nil, order: .post, arguments: arguments)
    }

    /// Returns a target action that gets executed after the sources and resources build phase.
    ///
    /// - Parameters:
    ///   - tool: Name of the tool to execute. Tuist will look up the tool on the environment's PATH.
    ///   - arguments: Arguments that to be passed.
    ///   - name: Name of the build phase when the project gets generated.
    /// - Returns: Target action.
    public static func post(tool: String, arguments: [String], name: String) -> TargetAction {
        return TargetAction(name: name, tool: tool, path: nil, order: .post, arguments: arguments)
    }

    /// Returns a target action that gets executed after the sources and resources build phase.
    ///
    /// - Parameters:
    ///   - path: Path to the script to execute.
    ///   - arguments: Arguments that to be passed.
    ///   - name: Name of the build phase when the project gets generated.
    /// - Returns: Target action.
    public static func post(path: String, arguments: String..., name: String) -> TargetAction {
        return TargetAction(name: name, tool: nil, path: path, order: .post, arguments: arguments)
    }

    /// Returns a target action that gets executed after the sources and resources build phase.
    ///
    /// - Parameters:
    ///   - path: Path to the script to execute.
    ///   - arguments: Arguments that to be passed.
    ///   - name: Name of the build phase when the project gets generated.
    /// - Returns: Target action.
    public static func post(path: String, arguments: [String], name: String) -> TargetAction {
        return TargetAction(name: name, tool: nil, path: path, order: .post, arguments: arguments)
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        order = try container.decode(Order.self, forKey: .order)
        arguments = try container.decode([String].self, forKey: .arguments)
        if let path = try container.decodeIfPresent(String.self, forKey: .path) {
            self.path = path
            tool = nil
        } else {
            path = nil
            tool = try container.decode(String.self, forKey: .tool)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(name, forKey: .name)
        try container.encode(order, forKey: .order)
        try container.encode(arguments, forKey: .arguments)

        if let tool = tool {
            try container.encode(tool, forKey: .tool)
        }
        if let path = path {
            try container.encode(path, forKey: .path)
        }
    }
}
