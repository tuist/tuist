import Foundation

public struct TargetGenerationAction: Codable, Equatable {
    /// Order when the target generation action gets called.
    ///
    /// - pre: Before the target is generated.
    /// - post: After the target is generated.
    public enum Order: String, Codable, Equatable {
        case pre
        case post
    }

    /// Name of the tool to execute. Tuist will look up the tool on the environment's PATH.
    public let tool: String?

    /// Path to the script to execute.
    public let path: Path?

    /// Target generation action order.
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
    ///   - tool: Name of the tool to execute. Tuist will look up the tool on the environment's PATH.
    ///   - path: Path to the script to execute.
    ///   - order: Target generation action order.
    init(tool: String?, path: Path?, order: Order, arguments: [String]) {
        self.path = path
        self.tool = tool
        self.order = order
        self.arguments = arguments
    }

    /// Returns a target generation action that gets executed before the project is generated.
    ///
    /// - Parameters:
    ///   - tool: Name of the tool to execute. Tuist will look up the tool on the environment's PATH.
    ///   - arguments: Arguments that to be passed.
    /// - Returns: Target generation action.
    public static func pre(tool: String, arguments: String...) -> TargetGenerationAction {
        return TargetGenerationAction(tool: tool, path: nil, order: .pre, arguments: arguments)
    }

    /// Returns a target generation action that gets executed before the project is generated.
    ///
    /// - Parameters:
    ///   - tool: Name of the tool to execute. Tuist will look up the tool on the environment's PATH.
    ///   - arguments: Arguments that to be passed.
    /// - Returns: Target generation action.
    public static func pre(tool: String, arguments: [String]) -> TargetGenerationAction {
        return TargetGenerationAction(tool: tool, path: nil, order: .pre, arguments: arguments)
    }

    /// Returns a target generation action that gets executed before the project is generated.
    ///
    /// - Parameters:
    ///   - path: Path to the script to execute.
    ///   - arguments: Arguments that to be passed.
    /// - Returns: Target generation action.
    public static func pre(path: Path, arguments: String...) -> TargetGenerationAction {
        return TargetGenerationAction(tool: nil, path: path, order: .pre, arguments: arguments)
    }

    /// Returns a target generation action that gets executed before the project is generated.
    ///
    /// - Parameters:
    ///   - path: Path to the script to execute.
    ///   - arguments: Arguments that to be passed.
    /// - Returns: Target generation action.
    public static func pre(path: Path, arguments: [String]) -> TargetGenerationAction {
        return TargetGenerationAction(tool: nil, path: path, order: .pre, arguments: arguments)
    }

    /// Returns a target generation action that gets executed after the project is generated.
    ///
    /// - Parameters:
    ///   - tool: Name of the tool to execute. Tuist will look up the tool on the environment's PATH.
    ///   - arguments: Arguments that to be passed.
    /// - Returns: Target generation action.
    public static func post(tool: String, arguments: String...) -> TargetGenerationAction {
        return TargetGenerationAction(tool: tool, path: nil, order: .post, arguments: arguments)
    }

    /// Returns a target generation action that gets executed after the project is generated.
    ///
    /// - Parameters:
    ///   - tool: Name of the tool to execute. Tuist will look up the tool on the environment's PATH.
    ///   - arguments: Arguments that to be passed.
    /// - Returns: Target generation action.
    public static func post(tool: String, arguments: [String]) -> TargetGenerationAction {
        return TargetGenerationAction(tool: tool, path: nil, order: .post, arguments: arguments)
    }

    /// Returns a target generation action that gets executed after the project is generated.
    ///
    /// - Parameters:
    ///   - path: Path to the script to execute.
    ///   - arguments: Arguments that to be passed.
    /// - Returns: Target generation action.
    public static func post(path: Path, arguments: String...) -> TargetGenerationAction {
        return TargetGenerationAction(tool: nil, path: path, order: .post, arguments: arguments)
    }

    /// Returns a target generation action that gets executed after the project is generated.
    ///
    /// - Parameters:
    ///   - path: Path to the script to execute.
    ///   - arguments: Arguments that to be passed.
    /// - Returns: Target generation action.
    public static func post(path: Path, arguments: [String]) -> TargetGenerationAction {
        return TargetGenerationAction(tool: nil, path: path, order: .post, arguments: arguments)
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        order = try container.decode(Order.self, forKey: .order)
        arguments = try container.decode([String].self, forKey: .arguments)
        if let path = try container.decodeIfPresent(Path.self, forKey: .path) {
            self.path = path
            tool = nil
        } else {
            path = nil
            tool = try container.decode(String.self, forKey: .tool)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

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
