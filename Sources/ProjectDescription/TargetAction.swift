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

    /// How to execute the target action
    ///
    /// - file: Executes the tool, calling the script at the path. Tuist will look up the tool on the environment's PATH
    /// - text: Executes the embedded script. This should be a short command.
    private enum Script: Equatable {
        case externalFile(_ tool: String?, _ path: Path?, _ args: [String])
        case embedded(String)
    }

    /// Name of the build phase when the project gets generated.
    public let name: String

    /// The script to execute in the action
    private let script: Script

    /// The text of the embedded script
    public var embeddedScript: String? {
        if case Script.embedded(let embeddedScript) = self.script {
            return embeddedScript
        }

        return nil
    }

    /// Name of the tool to execute. Tuist will look up the tool on the environment's PATH.
    public var tool: String? {
        if case Script.externalFile(let tool, _, _) = self.script {
            return tool
        }

        return nil
    }

    /// Path to the script to execute.
    public var path: Path? {
        if case Script.externalFile(_, let path, _) = self.script {
            return path
        }

        return nil
    }

    /// Target action order.
    public let order: Order

    /// Arguments that to be passed.
    public var arguments: [String] {
        if case Script.externalFile(_, _, let args) = self.script {
            return args
        }

        return []
    }

    /// List of input file paths
    public let inputPaths: [Path]

    /// List of input filelist paths
    public let inputFileListPaths: [Path]

    /// List of output file paths
    public let outputPaths: [Path]

    /// List of output filelist paths
    public let outputFileListPaths: [Path]

    /// Whether to skip running this script in incremental builds, if nothing has changed
    public let basedOnDependencyAnalysis: Bool?

    public enum CodingKeys: String, CodingKey {
        case name
        case tool
        case path
        case script
        case order
        case arguments
        case inputPaths
        case inputFileListPaths
        case outputPaths
        case outputFileListPaths
        case basedOnDependencyAnalysis
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
    ///   - basedOnDependencyAnalysis: Whether to skip running this script in incremental builds
    init(name: String,
         tool: String?,
         path: Path?,
         order: Order,
         arguments: [String],
         inputPaths: [Path] = [],
         inputFileListPaths: [Path] = [],
         outputPaths: [Path] = [],
         outputFileListPaths: [Path] = [],
         basedOnDependencyAnalysis: Bool? = nil)
    {
        self.name = name
        self.script = .externalFile(tool, path, arguments)
        self.order = order
        self.inputPaths = inputPaths
        self.inputFileListPaths = inputFileListPaths
        self.outputPaths = outputPaths
        self.outputFileListPaths = outputFileListPaths
        self.basedOnDependencyAnalysis = basedOnDependencyAnalysis
    }

    /// Initializes the target action with its attributes.
    ///
    /// - Parameters:
    ///   - name: Name of the build phase when the project gets generated.
    ///   - script: The text of the script to run. This should be kept small.
    ///   - order: Target action order.
    ///   - inputPaths: List of input file paths.
    ///   - inputFileListPaths: List of input filelist paths.
    ///   - outputPaths: List of output file paths.
    ///   - outputFileListPaths: List of output filelist paths.
    ///   - basedOnDependencyAnalysis: Whether to skip running this script in incremental builds
    init(name: String,
         script: String,
         order: Order,
         inputPaths: [Path] = [],
         inputFileListPaths: [Path] = [],
         outputPaths: [Path] = [],
         outputFileListPaths: [Path] = [],
         basedOnDependencyAnalysis: Bool? = nil)
    {
        self.name = name
        self.script = .embedded(script)
        self.order = order
        self.inputPaths = inputPaths
        self.inputFileListPaths = inputFileListPaths
        self.outputPaths = outputPaths
        self.outputFileListPaths = outputFileListPaths
        self.basedOnDependencyAnalysis = basedOnDependencyAnalysis
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
    ///   - basedOnDependencyAnalysis: Whether to skip running this script in incremental builds
    /// - Returns: Target action.
    public static func pre(tool: String,
                           arguments: String...,
                           name: String,
                           inputPaths: [Path] = [],
                           inputFileListPaths: [Path] = [],
                           outputPaths: [Path] = [],
                           outputFileListPaths: [Path] = [],
                           basedOnDependencyAnalysis: Bool? = nil) -> TargetAction
    {
        TargetAction(name: name,
                     tool: tool,
                     path: nil,
                     order: .pre,
                     arguments: arguments,
                     inputPaths: inputPaths,
                     inputFileListPaths: inputFileListPaths,
                     outputPaths: outputPaths,
                     outputFileListPaths: outputFileListPaths,
                     basedOnDependencyAnalysis: basedOnDependencyAnalysis)
    }

    /// Returns a target action that gets executed before the sources and resources build phase.
    ///
    /// - Parameters:
    ///   - script: The text of the script to run. This should be kept small.
    ///   - arguments: Arguments that to be passed.
    ///   - name: Name of the build phase when the project gets generated.
    ///   - inputPaths: List of input file paths.
    ///   - inputFileListPaths: List of input filelist paths.
    ///   - outputPaths: List of output file paths.
    ///   - outputFileListPaths: List of output filelist paths.
    ///   - basedOnDependencyAnalysis: Whether to skip running this script in incremental builds
    /// - Returns: Target action.
    public static func pre(script: String,
                           name: String,
                           inputPaths: [Path] = [],
                           inputFileListPaths: [Path] = [],
                           outputPaths: [Path] = [],
                           outputFileListPaths: [Path] = [],
                           basedOnDependencyAnalysis: Bool? = nil) -> TargetAction
    {
        TargetAction(name: name,
                     script: script,
                     order: .pre,
                     inputPaths: inputPaths,
                     inputFileListPaths: inputFileListPaths,
                     outputPaths: outputPaths,
                     outputFileListPaths: outputFileListPaths,
                     basedOnDependencyAnalysis: basedOnDependencyAnalysis)
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
    ///   - basedOnDependencyAnalysis: Whether to skip running this script in incremental builds
    /// - Returns: Target action.
    public static func pre(tool: String,
                           arguments: [String],
                           name: String,
                           inputPaths: [Path] = [],
                           inputFileListPaths: [Path] = [],
                           outputPaths: [Path] = [],
                           outputFileListPaths: [Path] = [],
                           basedOnDependencyAnalysis: Bool? = nil) -> TargetAction
    {
        TargetAction(name: name,
                     tool: tool,
                     path: nil,
                     order: .pre,
                     arguments: arguments,
                     inputPaths: inputPaths,
                     inputFileListPaths: inputFileListPaths,
                     outputPaths: outputPaths,
                     outputFileListPaths: outputFileListPaths,
                     basedOnDependencyAnalysis: basedOnDependencyAnalysis)
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
    ///   - basedOnDependencyAnalysis: Whether to skip running this script in incremental builds
    /// - Returns: Target action.
    public static func pre(path: Path,
                           arguments: String...,
                           name: String,
                           inputPaths: [Path] = [],
                           inputFileListPaths: [Path] = [],
                           outputPaths: [Path] = [],
                           outputFileListPaths: [Path] = [],
                           basedOnDependencyAnalysis: Bool? = nil) -> TargetAction
    {
        TargetAction(name: name,
                     tool: nil,
                     path: path,
                     order: .pre,
                     arguments: arguments,
                     inputPaths: inputPaths,
                     inputFileListPaths: inputFileListPaths,
                     outputPaths: outputPaths,
                     outputFileListPaths: outputFileListPaths,
                     basedOnDependencyAnalysis: basedOnDependencyAnalysis)
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
    ///   - basedOnDependencyAnalysis: Whether to skip running this script in incremental builds
    /// - Returns: Target action.
    public static func pre(path: Path,
                           arguments: [String],
                           name: String,
                           inputPaths: [Path] = [],
                           inputFileListPaths: [Path] = [],
                           outputPaths: [Path] = [],
                           outputFileListPaths: [Path] = [],
                           basedOnDependencyAnalysis: Bool? = nil) -> TargetAction
    {
        TargetAction(name: name,
                     tool: nil,
                     path: path,
                     order: .pre,
                     arguments: arguments,
                     inputPaths: inputPaths,
                     inputFileListPaths: inputFileListPaths,
                     outputPaths: outputPaths,
                     outputFileListPaths: outputFileListPaths,
                     basedOnDependencyAnalysis: basedOnDependencyAnalysis)
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
    ///   - basedOnDependencyAnalysis: Whether to skip running this script in incremental builds
    /// - Returns: Target action.
    public static func post(tool: String,
                            arguments: String...,
                            name: String,
                            inputPaths: [Path] = [],
                            inputFileListPaths: [Path] = [],
                            outputPaths: [Path] = [],
                            outputFileListPaths: [Path] = [],
                            basedOnDependencyAnalysis: Bool? = nil) -> TargetAction
    {
        TargetAction(name: name,
                     tool: tool,
                     path: nil,
                     order: .post,
                     arguments: arguments,
                     inputPaths: inputPaths,
                     inputFileListPaths: inputFileListPaths,
                     outputPaths: outputPaths,
                     outputFileListPaths: outputFileListPaths,
                     basedOnDependencyAnalysis: basedOnDependencyAnalysis)
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
    ///   - basedOnDependencyAnalysis: Whether to skip running this script in incremental builds
    /// - Returns: Target action.
    public static func post(tool: String,
                            arguments: [String],
                            name: String,
                            inputPaths: [Path] = [],
                            inputFileListPaths: [Path] = [],
                            outputPaths: [Path] = [],
                            outputFileListPaths: [Path] = [],
                            basedOnDependencyAnalysis: Bool? = nil) -> TargetAction
    {
        TargetAction(name: name,
                     tool: tool,
                     path: nil,
                     order: .post,
                     arguments: arguments,
                     inputPaths: inputPaths,
                     inputFileListPaths: inputFileListPaths,
                     outputPaths: outputPaths,
                     outputFileListPaths: outputFileListPaths,
                     basedOnDependencyAnalysis: basedOnDependencyAnalysis)
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
    ///   - basedOnDependencyAnalysis: Whether to skip running this script in incremental builds
    /// - Returns: Target action.
    public static func post(path: Path,
                            arguments: String...,
                            name: String,
                            inputPaths: [Path] = [],
                            inputFileListPaths: [Path] = [],
                            outputPaths: [Path] = [],
                            outputFileListPaths: [Path] = [],
                            basedOnDependencyAnalysis: Bool? = nil) -> TargetAction
    {
        TargetAction(name: name,
                     tool: nil,
                     path: path,
                     order: .post,
                     arguments: arguments,
                     inputPaths: inputPaths,
                     inputFileListPaths: inputFileListPaths,
                     outputPaths: outputPaths,
                     outputFileListPaths: outputFileListPaths,
                     basedOnDependencyAnalysis: basedOnDependencyAnalysis)
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
    ///   - basedOnDependencyAnalysis: Whether to skip running this script in incremental builds
    /// - Returns: Target action.
    public static func post(path: Path,
                            arguments: [String],
                            name: String,
                            inputPaths: [Path] = [],
                            inputFileListPaths: [Path] = [],
                            outputPaths: [Path] = [],
                            outputFileListPaths: [Path] = [],
                            basedOnDependencyAnalysis: Bool? = nil) -> TargetAction
    {
        TargetAction(name: name,
                     tool: nil,
                     path: path,
                     order: .post,
                     arguments: arguments,
                     inputPaths: inputPaths,
                     inputFileListPaths: inputFileListPaths,
                     outputPaths: outputPaths,
                     outputFileListPaths: outputFileListPaths,
                     basedOnDependencyAnalysis: basedOnDependencyAnalysis)
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
    ///   - basedOnDependencyAnalysis: Whether to skip running this script in incremental builds
    /// - Returns: Target action.
    public static func post(script: String,
                            name: String,
                            inputPaths: [Path] = [],
                            inputFileListPaths: [Path] = [],
                            outputPaths: [Path] = [],
                            outputFileListPaths: [Path] = [],
                            basedOnDependencyAnalysis: Bool? = nil) -> TargetAction
    {
        TargetAction(name: name,
                     script: script,
                     order: .post,
                     inputPaths: inputPaths,
                     inputFileListPaths: inputFileListPaths,
                     outputPaths: outputPaths,
                     outputFileListPaths: outputFileListPaths,
                     basedOnDependencyAnalysis: basedOnDependencyAnalysis)
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        order = try container.decode(Order.self, forKey: .order)
        inputPaths = try container.decodeIfPresent([Path].self, forKey: .inputPaths) ?? []
        inputFileListPaths = try container.decodeIfPresent([Path].self, forKey: .inputFileListPaths) ?? []
        outputPaths = try container.decodeIfPresent([Path].self, forKey: .outputPaths) ?? []
        outputFileListPaths = try container.decodeIfPresent([Path].self, forKey: .outputFileListPaths) ?? []
        basedOnDependencyAnalysis = try container.decodeIfPresent(Bool.self, forKey: .basedOnDependencyAnalysis)

        let arguments: [String] = try container.decodeIfPresent([String].self, forKey: .arguments) ?? []
        if let script = try container.decodeIfPresent(String.self, forKey: .script) {
            self.script = .embedded(script)
        } else if let path = try container.decodeIfPresent(Path.self, forKey: .path) {
            self.script = .externalFile(nil, path, arguments)
        } else {
            let tool = try container.decode(String.self, forKey: .tool)
            self.script = .externalFile(tool, nil, arguments)
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
        try container.encode(basedOnDependencyAnalysis, forKey: .basedOnDependencyAnalysis)

        if let tool = tool {
            try container.encode(tool, forKey: .tool)
        }
        if let path = path {
            try container.encode(path, forKey: .path)
        }
        if case Script.embedded(let text) = script {
            try container.encode(text, forKey: .script)
        }
    }
}
