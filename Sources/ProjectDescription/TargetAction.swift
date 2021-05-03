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

    /// Specifies how to execute the target action
    ///
    /// - tool: Executes the tool with the given arguments. Tuist will look up the tool on the environment's PATH.
    /// - scriptPath: Executes the file at the path with the given arguments.
    /// - text: Executes the embedded script. This should be a short command.
    public enum Script: Equatable {
        case tool(_ path: String, _ args: [String] = [])
        case scriptPath(_ path: Path, args: [String] = [])
        case embedded(String)
    }

    /// Name of the build phase when the project gets generated.
    public let name: String

    /// The action that is to be executed
    public let script: Script

    /// Target action order.
    public let order: Order

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

    /// Whether this action only runs on install builds (default is false)
    public let runForInstallBuildsOnly: Bool

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
        case runForInstallBuildsOnly = "runOnlyForDeploymentPostprocessing"
    }

    /// Initializes the target action with its attributes.
    ///
    /// - Parameters:
    ///   - name: Name of the build phase when the project gets generated.
    ///   - script: The script to be executed.
    ///   - arguments: Arguments that to be passed.
    ///   - inputPaths: List of input file paths.
    ///   - inputFileListPaths: List of input filelist paths.
    ///   - outputPaths: List of output file paths.
    ///   - outputFileListPaths: List of output filelist paths.
    ///   - basedOnDependencyAnalysis: Whether to skip running this script in incremental builds
    ///   - runForInstallBuildsOnly: Whether this action only runs on install builds (default is false)
    init(name: String,
         script: Script = .embedded(""),
         order: Order,
         inputPaths: [Path] = [],
         inputFileListPaths: [Path] = [],
         outputPaths: [Path] = [],
         outputFileListPaths: [Path] = [],
         basedOnDependencyAnalysis: Bool? = nil,
         runForInstallBuildsOnly: Bool = false)
    {
        self.name = name
        self.script = script
        self.order = order
        self.inputPaths = inputPaths
        self.inputFileListPaths = inputFileListPaths
        self.outputPaths = outputPaths
        self.outputFileListPaths = outputFileListPaths
        self.basedOnDependencyAnalysis = basedOnDependencyAnalysis
        self.runForInstallBuildsOnly = runForInstallBuildsOnly
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
        runForInstallBuildsOnly = try container.decodeIfPresent(Bool.self, forKey: .runForInstallBuildsOnly) ?? false

        let arguments: [String] = try container.decodeIfPresent([String].self, forKey: .arguments) ?? []
        if let script = try container.decodeIfPresent(String.self, forKey: .script) {
            self.script = .embedded(script)
        } else if let path = try container.decodeIfPresent(Path.self, forKey: .path) {
            script = .scriptPath(path, args: arguments)
        } else if let tool = try container.decodeIfPresent(String.self, forKey: .tool) {
            script = .tool(tool, arguments)
        } else {
            script = .embedded("echo 'No embedded script, path to a script, or tool was found'")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(name, forKey: .name)
        try container.encode(order, forKey: .order)
        try container.encode(inputPaths, forKey: .inputPaths)
        try container.encode(inputFileListPaths, forKey: .inputFileListPaths)
        try container.encode(outputPaths, forKey: .outputPaths)
        try container.encode(outputFileListPaths, forKey: .outputFileListPaths)
        try container.encode(basedOnDependencyAnalysis, forKey: .basedOnDependencyAnalysis)
        try container.encode(runForInstallBuildsOnly, forKey: .runForInstallBuildsOnly)

        switch script {
        case let .embedded(script):
            try container.encode(script, forKey: .script)

        case let .scriptPath(path, args: args):
            try container.encode(path, forKey: .path)
            try container.encode(args, forKey: .arguments)

        case let .tool(tool, args):
            try container.encode(tool, forKey: .tool)
            try container.encode(args, forKey: .arguments)
        }
    }
}

// MARK: Tools init

extension TargetAction {
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
    ///   - runForInstallBuildsOnly: Whether this action only runs on install builds (default is false)
    /// - Returns: Target action.
    public static func pre(tool: String,
                           arguments: String...,
                           name: String,
                           inputPaths: [Path] = [],
                           inputFileListPaths: [Path] = [],
                           outputPaths: [Path] = [],
                           outputFileListPaths: [Path] = [],
                           basedOnDependencyAnalysis: Bool? = nil,
                           runForInstallBuildsOnly: Bool = false) -> TargetAction
    {
        TargetAction(
            name: name,
            script: .tool(tool, arguments),
            order: .pre,
            inputPaths: inputPaths,
            inputFileListPaths: inputFileListPaths,
            outputPaths: outputPaths,
            outputFileListPaths: outputFileListPaths,
            basedOnDependencyAnalysis: basedOnDependencyAnalysis,
            runForInstallBuildsOnly: runForInstallBuildsOnly
        )
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
    ///   - runForInstallBuildsOnly: Whether this action only runs on install builds (default is false)
    /// - Returns: Target action.
    public static func pre(tool: String,
                           arguments: [String],
                           name: String,
                           inputPaths: [Path] = [],
                           inputFileListPaths: [Path] = [],
                           outputPaths: [Path] = [],
                           outputFileListPaths: [Path] = [],
                           basedOnDependencyAnalysis: Bool? = nil,
                           runForInstallBuildsOnly: Bool = false) -> TargetAction
    {
        TargetAction(
            name: name,
            script: .tool(tool, arguments),
            order: .pre,
            inputPaths: inputPaths,
            inputFileListPaths: inputFileListPaths,
            outputPaths: outputPaths,
            outputFileListPaths: outputFileListPaths,
            basedOnDependencyAnalysis: basedOnDependencyAnalysis,
            runForInstallBuildsOnly: runForInstallBuildsOnly
        )
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
    ///   - runForInstallBuildsOnly: Whether this action only runs on install builds (default is false)
    /// - Returns: Target action.
    public static func post(tool: String,
                            arguments: String...,
                            name: String,
                            inputPaths: [Path] = [],
                            inputFileListPaths: [Path] = [],
                            outputPaths: [Path] = [],
                            outputFileListPaths: [Path] = [],
                            basedOnDependencyAnalysis: Bool? = nil,
                            runForInstallBuildsOnly: Bool = false) -> TargetAction
    {
        TargetAction(
            name: name,
            script: .tool(tool, arguments),
            order: .post,
            inputPaths: inputPaths,
            inputFileListPaths: inputFileListPaths,
            outputPaths: outputPaths,
            outputFileListPaths: outputFileListPaths,
            basedOnDependencyAnalysis: basedOnDependencyAnalysis,
            runForInstallBuildsOnly: runForInstallBuildsOnly
        )
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
    ///   - runForInstallBuildsOnly: Whether this action only runs on install builds (default is false)
    /// - Returns: Target action.
    public static func post(tool: String,
                            arguments: [String],
                            name: String,
                            inputPaths: [Path] = [],
                            inputFileListPaths: [Path] = [],
                            outputPaths: [Path] = [],
                            outputFileListPaths: [Path] = [],
                            basedOnDependencyAnalysis: Bool? = nil,
                            runForInstallBuildsOnly: Bool = false) -> TargetAction
    {
        TargetAction(
            name: name,
            script: .tool(tool, arguments),
            order: .post,
            inputPaths: inputPaths,
            inputFileListPaths: inputFileListPaths,
            outputPaths: outputPaths,
            outputFileListPaths: outputFileListPaths,
            basedOnDependencyAnalysis: basedOnDependencyAnalysis,
            runForInstallBuildsOnly: runForInstallBuildsOnly
        )
    }
}

// MARK: Path init

extension TargetAction {
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
    ///   - runForInstallBuildsOnly: Whether this action only runs on install builds (default is false)
    /// - Returns: Target action.
    public static func pre(path: Path,
                           arguments: String...,
                           name: String,
                           inputPaths: [Path] = [],
                           inputFileListPaths: [Path] = [],
                           outputPaths: [Path] = [],
                           outputFileListPaths: [Path] = [],
                           basedOnDependencyAnalysis: Bool? = nil,
                           runForInstallBuildsOnly: Bool = false) -> TargetAction
    {
        TargetAction(
            name: name,
            script: .scriptPath(path, args: arguments),
            order: .pre,
            inputPaths: inputPaths,
            inputFileListPaths: inputFileListPaths,
            outputPaths: outputPaths,
            outputFileListPaths: outputFileListPaths,
            basedOnDependencyAnalysis: basedOnDependencyAnalysis,
            runForInstallBuildsOnly: runForInstallBuildsOnly
        )
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
    ///   - runForInstallBuildsOnly: Whether this action only runs on install builds (default is false)
    /// - Returns: Target action.
    public static func pre(path: Path,
                           arguments: [String],
                           name: String,
                           inputPaths: [Path] = [],
                           inputFileListPaths: [Path] = [],
                           outputPaths: [Path] = [],
                           outputFileListPaths: [Path] = [],
                           basedOnDependencyAnalysis: Bool? = nil,
                           runForInstallBuildsOnly: Bool = false) -> TargetAction
    {
        TargetAction(
            name: name,
            script: .scriptPath(path, args: arguments),
            order: .pre,
            inputPaths: inputPaths,
            inputFileListPaths: inputFileListPaths,
            outputPaths: outputPaths,
            outputFileListPaths: outputFileListPaths,
            basedOnDependencyAnalysis: basedOnDependencyAnalysis,
            runForInstallBuildsOnly: runForInstallBuildsOnly
        )
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
    ///   - runForInstallBuildsOnly: Whether this action only runs on install builds (default is false)
    /// - Returns: Target action.
    public static func post(path: Path,
                            arguments: String...,
                            name: String,
                            inputPaths: [Path] = [],
                            inputFileListPaths: [Path] = [],
                            outputPaths: [Path] = [],
                            outputFileListPaths: [Path] = [],
                            basedOnDependencyAnalysis: Bool? = nil,
                            runForInstallBuildsOnly: Bool = false) -> TargetAction
    {
        TargetAction(
            name: name,
            script: .scriptPath(path, args: arguments),
            order: .post,
            inputPaths: inputPaths,
            inputFileListPaths: inputFileListPaths,
            outputPaths: outputPaths,
            outputFileListPaths: outputFileListPaths,
            basedOnDependencyAnalysis: basedOnDependencyAnalysis,
            runForInstallBuildsOnly: runForInstallBuildsOnly
        )
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
    ///   - runForInstallBuildsOnly: Whether this action only runs on install builds (default is false)
    /// - Returns: Target action.
    public static func post(path: Path,
                            arguments: [String],
                            name: String,
                            inputPaths: [Path] = [],
                            inputFileListPaths: [Path] = [],
                            outputPaths: [Path] = [],
                            outputFileListPaths: [Path] = [],
                            basedOnDependencyAnalysis: Bool? = nil,
                            runForInstallBuildsOnly: Bool = false) -> TargetAction
    {
        TargetAction(
            name: name,
            script: .scriptPath(path, args: arguments),
            order: .post,
            inputPaths: inputPaths,
            inputFileListPaths: inputFileListPaths,
            outputPaths: outputPaths,
            outputFileListPaths: outputFileListPaths,
            basedOnDependencyAnalysis: basedOnDependencyAnalysis,
            runForInstallBuildsOnly: runForInstallBuildsOnly
        )
    }
}

// MARK: Embedded script init

extension TargetAction {
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
    ///   - runForInstallBuildsOnly: Whether this action only runs on install builds (default is false)
    /// - Returns: Target action.
    public static func pre(script: String,
                           name: String,
                           inputPaths: [Path] = [],
                           inputFileListPaths: [Path] = [],
                           outputPaths: [Path] = [],
                           outputFileListPaths: [Path] = [],
                           basedOnDependencyAnalysis: Bool? = nil,
                           runForInstallBuildsOnly: Bool = false) -> TargetAction
    {
        TargetAction(
            name: name,
            script: .embedded(script),
            order: .pre,
            inputPaths: inputPaths,
            inputFileListPaths: inputFileListPaths,
            outputPaths: outputPaths,
            outputFileListPaths: outputFileListPaths,
            basedOnDependencyAnalysis: basedOnDependencyAnalysis,
            runForInstallBuildsOnly: runForInstallBuildsOnly
        )
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
    ///   - runForInstallBuildsOnly: Whether this action only runs on install builds (default is false)
    /// - Returns: Target action.
    public static func post(script: String,
                            name: String,
                            inputPaths: [Path] = [],
                            inputFileListPaths: [Path] = [],
                            outputPaths: [Path] = [],
                            outputFileListPaths: [Path] = [],
                            basedOnDependencyAnalysis: Bool? = nil,
                            runForInstallBuildsOnly: Bool = false) -> TargetAction
    {
        TargetAction(
            name: name,
            script: .embedded(script),
            order: .post,
            inputPaths: inputPaths,
            inputFileListPaths: inputFileListPaths,
            outputPaths: outputPaths,
            outputFileListPaths: outputFileListPaths,
            basedOnDependencyAnalysis: basedOnDependencyAnalysis,
            runForInstallBuildsOnly: runForInstallBuildsOnly
        )
    }
}
