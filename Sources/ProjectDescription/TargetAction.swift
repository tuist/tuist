import Foundation

public struct TargetAction: Codable, Equatable {
    /// Order when the action gets executed.
    ///
    /// - pre: Before the sources and resources build phase.
    /// - post: After the sources and resources build phase.
    public enum Order: String, Codable, Equatable {
        case pre
        case post
    }

    /// Name of the build phase when the project gets generated.
    public let name: String

    /// Name of the tool to execute. Tuist will look up the tool on the environment's PATH.
    public let tool: String?

    /// Path to the script to execute.
    public let path: Path?

    /// Target action order.
    public let order: Order

    /// Arguments that to be passed.
    public let arguments: [String]

    /// List of input file paths
    public let inputPaths: [Path]

    /// List of input filelist paths
    public let inputFileListPaths: [Path]

    /// List of output file paths
    public let outputPaths: [Path]

    /// List of output filelist paths
    public let outputFileListPaths: [Path]

    public enum CodingKeys: String, CodingKey {
        case name
        case tool
        case path
        case order
        case arguments
        case inputPaths
        case inputFileListPaths
        case outputPaths
        case outputFileListPaths
    }

    /// Initializes the target action with its attributes.
    ///
    /// - Parameters:
    ///   - name: Name of the build phase when the project gets generated.
    ///   - tool: Name of the tool to execute. Tuist will look up the tool on the environment's PATH.
    ///   - path: Path to the script to execute.
    ///   - order: Target action order.
    ///   - arguments: Arguments that to be passed.
    ///   - inputPaths: List of input file paths.
    ///   - inputFileListPaths: List of input filelist paths.
    ///   - outputPaths: List of output file paths.
    ///   - outputFileListPaths: List of output filelist paths.
    init(name: String,
         tool: String?,
         path: Path?,
         order: Order,
         arguments: [String],
         inputPaths: [Path] = [],
         inputFileListPaths: [Path] = [],
         outputPaths: [Path] = [],
         outputFileListPaths: [Path] = [])
    {
        self.name = name
        self.path = path
        self.tool = tool
        self.order = order
        self.arguments = arguments
        self.inputPaths = inputPaths
        self.inputFileListPaths = inputFileListPaths
        self.outputPaths = outputPaths
        self.outputFileListPaths = outputFileListPaths
    }

    /// Returns a target action that gets executed before the sources and resources build phase.
    ///
    /// - Parameters:
    ///   - tool: Name of the tool to execute. Tuist will look up the tool on the environment's PATH.
    ///   - arguments: Arguments that to be passed.
    ///   - name: Name of the build phase when the project gets generated.
    ///   - inputPaths: List of input file paths.
    ///   - inputFileListPaths: List of input filelist paths.
    ///   - outputPaths: List of output file paths.
    ///   - outputFileListPaths: List of output filelist paths.
    /// - Returns: Target action.
    public static func pre(tool: String,
                           arguments: String...,
                           name: String,
                           inputPaths: [Path] = [],
                           inputFileListPaths: [Path] = [],
                           outputPaths: [Path] = [],
                           outputFileListPaths: [Path] = []) -> TargetAction
    {
        TargetAction(name: name,
                     tool: tool,
                     path: nil,
                     order: .pre,
                     arguments: arguments,
                     inputPaths: inputPaths,
                     inputFileListPaths: inputFileListPaths,
                     outputPaths: outputPaths,
                     outputFileListPaths: outputFileListPaths)
    }

    /// Returns a target action that gets executed before the sources and resources build phase.
    ///
    /// - Parameters:
    ///   - tool: Name of the tool to execute. Tuist will look up the tool on the environment's PATH.
    ///   - arguments: Arguments that to be passed.
    ///   - name: Name of the build phase when the project gets generated.
    ///   - inputPaths: List of input file paths.
    ///   - inputFileListPaths: List of input filelist paths.
    ///   - outputPaths: List of output file paths.
    ///   - outputFileListPaths: List of output filelist paths.
    /// - Returns: Target action.
    public static func pre(tool: String,
                           arguments: [String],
                           name: String,
                           inputPaths: [Path] = [],
                           inputFileListPaths: [Path] = [],
                           outputPaths: [Path] = [],
                           outputFileListPaths: [Path] = []) -> TargetAction
    {
        TargetAction(name: name,
                     tool: tool,
                     path: nil,
                     order: .pre,
                     arguments: arguments,
                     inputPaths: inputPaths,
                     inputFileListPaths: inputFileListPaths,
                     outputPaths: outputPaths,
                     outputFileListPaths: outputFileListPaths)
    }

    /// Returns a target action that gets executed before the sources and resources build phase.
    ///
    /// - Parameters:
    ///   - path: Path to the script to execute.
    ///   - arguments: Arguments that to be passed.
    ///   - name: Name of the build phase when the project gets generated.
    ///   - inputPaths: List of input file paths.
    ///   - inputFileListPaths: List of input filelist paths.
    ///   - outputPaths: List of output file paths.
    ///   - outputFileListPaths: List of output filelist paths.
    /// - Returns: Target action.
    public static func pre(path: Path,
                           arguments: String...,
                           name: String,
                           inputPaths: [Path] = [],
                           inputFileListPaths: [Path] = [],
                           outputPaths: [Path] = [],
                           outputFileListPaths: [Path] = []) -> TargetAction
    {
        TargetAction(name: name,
                     tool: nil,
                     path: path,
                     order: .pre,
                     arguments: arguments,
                     inputPaths: inputPaths,
                     inputFileListPaths: inputFileListPaths,
                     outputPaths: outputPaths,
                     outputFileListPaths: outputFileListPaths)
    }

    /// Returns a target action that gets executed before the sources and resources build phase.
    ///
    /// - Parameters:
    ///   - path: Path to the script to execute.
    ///   - arguments: Arguments that to be passed.
    ///   - name: Name of the build phase when the project gets generated.
    ///   - inputPaths: List of input file paths.
    ///   - inputFileListPaths: List of input filelist paths.
    ///   - outputPaths: List of output file paths.
    ///   - outputFileListPaths: List of output filelist paths.
    /// - Returns: Target action.
    public static func pre(path: Path,
                           arguments: [String],
                           name: String,
                           inputPaths: [Path] = [],
                           inputFileListPaths: [Path] = [],
                           outputPaths: [Path] = [],
                           outputFileListPaths: [Path] = []) -> TargetAction
    {
        TargetAction(name: name,
                     tool: nil,
                     path: path,
                     order: .pre,
                     arguments: arguments,
                     inputPaths: inputPaths,
                     inputFileListPaths: inputFileListPaths,
                     outputPaths: outputPaths,
                     outputFileListPaths: outputFileListPaths)
    }

    /// Returns a target action that gets executed after the sources and resources build phase.
    ///
    /// - Parameters:
    ///   - tool: Name of the tool to execute. Tuist will look up the tool on the environment's PATH.
    ///   - arguments: Arguments that to be passed.
    ///   - name: Name of the build phase when the project gets generated.
    ///   - inputPaths: List of input file paths.
    ///   - inputFileListPaths: List of input filelist paths.
    ///   - outputPaths: List of output file paths.
    ///   - outputFileListPaths: List of output filelist paths.
    /// - Returns: Target action.
    public static func post(tool: String,
                            arguments: String...,
                            name: String,
                            inputPaths: [Path] = [],
                            inputFileListPaths: [Path] = [],
                            outputPaths: [Path] = [],
                            outputFileListPaths: [Path] = []) -> TargetAction
    {
        TargetAction(name: name,
                     tool: tool,
                     path: nil,
                     order: .post,
                     arguments: arguments,
                     inputPaths: inputPaths,
                     inputFileListPaths: inputFileListPaths,
                     outputPaths: outputPaths,
                     outputFileListPaths: outputFileListPaths)
    }

    /// Returns a target action that gets executed after the sources and resources build phase.
    ///
    /// - Parameters:
    ///   - tool: Name of the tool to execute. Tuist will look up the tool on the environment's PATH.
    ///   - arguments: Arguments that to be passed.
    ///   - name: Name of the build phase when the project gets generated.
    ///   - inputPaths: List of input file paths.
    ///   - inputFileListPaths: List of input filelist paths.
    ///   - outputPaths: List of output file paths.
    ///   - outputFileListPaths: List of output filelist paths.
    /// - Returns: Target action.
    public static func post(tool: String,
                            arguments: [String],
                            name: String,
                            inputPaths: [Path] = [],
                            inputFileListPaths: [Path] = [],
                            outputPaths: [Path] = [],
                            outputFileListPaths: [Path] = []) -> TargetAction
    {
        TargetAction(name: name,
                     tool: tool,
                     path: nil,
                     order: .post,
                     arguments: arguments,
                     inputPaths: inputPaths,
                     inputFileListPaths: inputFileListPaths,
                     outputPaths: outputPaths,
                     outputFileListPaths: outputFileListPaths)
    }

    /// Returns a target action that gets executed after the sources and resources build phase.
    ///
    /// - Parameters:
    ///   - path: Path to the script to execute.
    ///   - arguments: Arguments that to be passed.
    ///   - name: Name of the build phase when the project gets generated.
    ///   - inputPaths: List of input file paths.
    ///   - inputFileListPaths: List of input filelist paths.
    ///   - outputPaths: List of output file paths.
    ///   - outputFileListPaths: List of output filelist paths.
    /// - Returns: Target action.
    public static func post(path: Path,
                            arguments: String...,
                            name: String,
                            inputPaths: [Path] = [],
                            inputFileListPaths: [Path] = [],
                            outputPaths: [Path] = [],
                            outputFileListPaths: [Path] = []) -> TargetAction
    {
        TargetAction(name: name,
                     tool: nil,
                     path: path,
                     order: .post,
                     arguments: arguments,
                     inputPaths: inputPaths,
                     inputFileListPaths: inputFileListPaths,
                     outputPaths: outputPaths,
                     outputFileListPaths: outputFileListPaths)
    }

    /// Returns a target action that gets executed after the sources and resources build phase.
    ///
    /// - Parameters:
    ///   - path: Path to the script to execute.
    ///   - arguments: Arguments that to be passed.
    ///   - name: Name of the build phase when the project gets generated.
    ///   - inputPaths: List of input file paths.
    ///   - inputFileListPaths: List of input filelist paths.
    ///   - outputPaths: List of output file paths.
    ///   - outputFileListPaths: List of output filelist paths.
    /// - Returns: Target action.
    public static func post(path: Path,
                            arguments: [String],
                            name: String,
                            inputPaths: [Path] = [],
                            inputFileListPaths: [Path] = [],
                            outputPaths: [Path] = [],
                            outputFileListPaths: [Path] = []) -> TargetAction
    {
        TargetAction(name: name,
                     tool: nil,
                     path: path,
                     order: .post,
                     arguments: arguments,
                     inputPaths: inputPaths,
                     inputFileListPaths: inputFileListPaths,
                     outputPaths: outputPaths,
                     outputFileListPaths: outputFileListPaths)
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        order = try container.decode(Order.self, forKey: .order)
        arguments = try container.decode([String].self, forKey: .arguments)
        inputPaths = try container.decodeIfPresent([Path].self, forKey: .inputPaths) ?? []
        inputFileListPaths = try container.decodeIfPresent([Path].self, forKey: .inputFileListPaths) ?? []
        outputPaths = try container.decodeIfPresent([Path].self, forKey: .outputPaths) ?? []
        outputFileListPaths = try container.decodeIfPresent([Path].self, forKey: .outputFileListPaths) ?? []
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

        try container.encode(name, forKey: .name)
        try container.encode(order, forKey: .order)
        try container.encode(arguments, forKey: .arguments)
        try container.encode(inputPaths, forKey: .inputPaths)
        try container.encode(inputFileListPaths, forKey: .inputFileListPaths)
        try container.encode(outputPaths, forKey: .outputPaths)
        try container.encode(outputFileListPaths, forKey: .outputFileListPaths)

        if let tool = tool {
            try container.encode(tool, forKey: .tool)
        }
        if let path = path {
            try container.encode(path, forKey: .path)
        }
    }
}
