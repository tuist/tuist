import Foundation

/// Target scripts, represented as target script build phases in the generated Xcode projects, are useful to define actions to be executed before of after the build process of a target.
// swiftlint:disable:next type_body_length
public struct TargetScript: Codable, Equatable {
    /// Order when the script gets executed.
    ///
    /// - pre: Before the sources and resources build phase.
    /// - post: After the sources and resources build phase.
    public enum Order: String, Codable, Equatable {
        case pre
        case post
    }

    /// Specifies how to execute the target script
    ///
    /// - tool: Executes the tool with the given arguments. Tuist will look up the tool on the environment's PATH.
    /// - scriptPath: Executes the file at the path with the given arguments.
    /// - text: Executes the embedded script. This should be a short command.
    public enum Script: Equatable, Codable {
        case tool(path: String, args: [String])
        case scriptPath(path: Path, args: [String])
        case embedded(String)
    }

    /// Name of the build phase when the project gets generated.
    public let name: String

    /// The script that is to be executed
    public let script: Script

    /// Target script order.
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

    /// Whether this script only runs on install builds (default is false)
    public let runForInstallBuildsOnly: Bool

    /// The path to the shell which shall execute this script.
    public let shellPath: String

    /// Initializes the target script with its attributes.
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
    ///   - runForInstallBuildsOnly: Whether this script only runs on install builds (default is false)
    ///   - shellPath: The path to the shell which shall execute this script. Default is `/bin/sh`.
    init(
        name: String,
        script: Script = .embedded(""),
        order: Order,
        inputPaths: [Path] = [],
        inputFileListPaths: [Path] = [],
        outputPaths: [Path] = [],
        outputFileListPaths: [Path] = [],
        basedOnDependencyAnalysis: Bool? = nil,
        runForInstallBuildsOnly: Bool = false,
        shellPath: String = "/bin/sh"
    ) {
        self.name = name
        self.script = script
        self.order = order
        self.inputPaths = inputPaths
        self.inputFileListPaths = inputFileListPaths
        self.outputPaths = outputPaths
        self.outputFileListPaths = outputFileListPaths
        self.basedOnDependencyAnalysis = basedOnDependencyAnalysis
        self.runForInstallBuildsOnly = runForInstallBuildsOnly
        self.shellPath = shellPath
    }

    // MARK: - Path init

    /// Returns a target script that gets executed before the sources and resources build phase.
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
    ///   - runForInstallBuildsOnly: Whether this script only runs on install builds (default is false)
    ///   - shellPath: The path to the shell which shall execute this script. Default is `/bin/sh`.
    /// - Returns: Target script.
    public static func pre(
        path: Path,
        arguments: String...,
        name: String,
        inputPaths: [Path] = [],
        inputFileListPaths: [Path] = [],
        outputPaths: [Path] = [],
        outputFileListPaths: [Path] = [],
        basedOnDependencyAnalysis: Bool? = nil,
        runForInstallBuildsOnly: Bool = false,
        shellPath: String = "/bin/sh"
    ) -> TargetScript {
        TargetScript(
            name: name,
            script: .scriptPath(path: path, args: arguments),
            order: .pre,
            inputPaths: inputPaths,
            inputFileListPaths: inputFileListPaths,
            outputPaths: outputPaths,
            outputFileListPaths: outputFileListPaths,
            basedOnDependencyAnalysis: basedOnDependencyAnalysis,
            runForInstallBuildsOnly: runForInstallBuildsOnly,
            shellPath: shellPath
        )
    }

    /// Returns a target script that gets executed before the sources and resources build phase.
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
    ///   - runForInstallBuildsOnly: Whether this script only runs on install builds (default is false)
    ///   - shellPath: The path to the shell which shall execute this script. Default is `/bin/sh`.
    /// - Returns: Target script.
    public static func pre(
        path: Path,
        arguments: [String],
        name: String,
        inputPaths: [Path] = [],
        inputFileListPaths: [Path] = [],
        outputPaths: [Path] = [],
        outputFileListPaths: [Path] = [],
        basedOnDependencyAnalysis: Bool? = nil,
        runForInstallBuildsOnly: Bool = false,
        shellPath: String = "/bin/sh"
    ) -> TargetScript {
        TargetScript(
            name: name,
            script: .scriptPath(path: path, args: arguments),
            order: .pre,
            inputPaths: inputPaths,
            inputFileListPaths: inputFileListPaths,
            outputPaths: outputPaths,
            outputFileListPaths: outputFileListPaths,
            basedOnDependencyAnalysis: basedOnDependencyAnalysis,
            runForInstallBuildsOnly: runForInstallBuildsOnly,
            shellPath: shellPath
        )
    }

    /// Returns a target script that gets executed after the sources and resources build phase.
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
    ///   - runForInstallBuildsOnly: Whether this script only runs on install builds (default is false)
    ///   - shellPath: The path to the shell which shall execute this script. Default is `/bin/sh`.
    /// - Returns: Target script.
    public static func post(
        path: Path,
        arguments: String...,
        name: String,
        inputPaths: [Path] = [],
        inputFileListPaths: [Path] = [],
        outputPaths: [Path] = [],
        outputFileListPaths: [Path] = [],
        basedOnDependencyAnalysis: Bool? = nil,
        runForInstallBuildsOnly: Bool = false,
        shellPath: String = "/bin/sh"
    ) -> TargetScript {
        TargetScript(
            name: name,
            script: .scriptPath(path: path, args: arguments),
            order: .post,
            inputPaths: inputPaths,
            inputFileListPaths: inputFileListPaths,
            outputPaths: outputPaths,
            outputFileListPaths: outputFileListPaths,
            basedOnDependencyAnalysis: basedOnDependencyAnalysis,
            runForInstallBuildsOnly: runForInstallBuildsOnly,
            shellPath: shellPath
        )
    }

    /// Returns a target script that gets executed after the sources and resources build phase.
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
    ///   - runForInstallBuildsOnly: Whether this script only runs on install builds (default is false)
    ///   - shellPath: The path to the shell which shall execute this script. Default is `/bin/sh`.
    /// - Returns: Target script.
    public static func post(
        path: Path,
        arguments: [String],
        name: String,
        inputPaths: [Path] = [],
        inputFileListPaths: [Path] = [],
        outputPaths: [Path] = [],
        outputFileListPaths: [Path] = [],
        basedOnDependencyAnalysis: Bool? = nil,
        runForInstallBuildsOnly: Bool = false,
        shellPath: String = "/bin/sh"
    ) -> TargetScript {
        TargetScript(
            name: name,
            script: .scriptPath(path: path, args: arguments),
            order: .post,
            inputPaths: inputPaths,
            inputFileListPaths: inputFileListPaths,
            outputPaths: outputPaths,
            outputFileListPaths: outputFileListPaths,
            basedOnDependencyAnalysis: basedOnDependencyAnalysis,
            runForInstallBuildsOnly: runForInstallBuildsOnly,
            shellPath: shellPath
        )
    }

    // MARK: - Tools init

    /// Returns a target script that gets executed before the sources and resources build phase.
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
    ///   - runForInstallBuildsOnly: Whether this script only runs on install builds (default is false)
    ///   - shellPath: The path to the shell which shall execute this script. Default is `/bin/sh`.
    /// - Returns: Target script.
    public static func pre(
        tool: String,
        arguments: String...,
        name: String,
        inputPaths: [Path] = [],
        inputFileListPaths: [Path] = [],
        outputPaths: [Path] = [],
        outputFileListPaths: [Path] = [],
        basedOnDependencyAnalysis: Bool? = nil,
        runForInstallBuildsOnly: Bool = false,
        shellPath: String = "/bin/sh"
    ) -> TargetScript {
        TargetScript(
            name: name,
            script: .tool(path: tool, args: arguments),
            order: .pre,
            inputPaths: inputPaths,
            inputFileListPaths: inputFileListPaths,
            outputPaths: outputPaths,
            outputFileListPaths: outputFileListPaths,
            basedOnDependencyAnalysis: basedOnDependencyAnalysis,
            runForInstallBuildsOnly: runForInstallBuildsOnly,
            shellPath: shellPath
        )
    }

    /// Returns a target script that gets executed before the sources and resources build phase.
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
    ///   - runForInstallBuildsOnly: Whether this script only runs on install builds (default is false)
    ///   - shellPath: The path to the shell which shall execute this script. Default is `/bin/sh`.
    /// - Returns: Target script.
    public static func pre(
        tool: String,
        arguments: [String],
        name: String,
        inputPaths: [Path] = [],
        inputFileListPaths: [Path] = [],
        outputPaths: [Path] = [],
        outputFileListPaths: [Path] = [],
        basedOnDependencyAnalysis: Bool? = nil,
        runForInstallBuildsOnly: Bool = false,
        shellPath: String = "/bin/sh"
    ) -> TargetScript {
        TargetScript(
            name: name,
            script: .tool(path: tool, args: arguments),
            order: .pre,
            inputPaths: inputPaths,
            inputFileListPaths: inputFileListPaths,
            outputPaths: outputPaths,
            outputFileListPaths: outputFileListPaths,
            basedOnDependencyAnalysis: basedOnDependencyAnalysis,
            runForInstallBuildsOnly: runForInstallBuildsOnly,
            shellPath: shellPath
        )
    }

    /// Returns a target script that gets executed after the sources and resources build phase.
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
    ///   - runForInstallBuildsOnly: Whether this script only runs on install builds (default is false)
    ///   - shellPath: The path to the shell which shall execute this script. Default is `/bin/sh`.
    /// - Returns: Target script.
    public static func post(
        tool: String,
        arguments: String...,
        name: String,
        inputPaths: [Path] = [],
        inputFileListPaths: [Path] = [],
        outputPaths: [Path] = [],
        outputFileListPaths: [Path] = [],
        basedOnDependencyAnalysis: Bool? = nil,
        runForInstallBuildsOnly: Bool = false,
        shellPath: String = "/bin/sh"
    ) -> TargetScript {
        TargetScript(
            name: name,
            script: .tool(path: tool, args: arguments),
            order: .post,
            inputPaths: inputPaths,
            inputFileListPaths: inputFileListPaths,
            outputPaths: outputPaths,
            outputFileListPaths: outputFileListPaths,
            basedOnDependencyAnalysis: basedOnDependencyAnalysis,
            runForInstallBuildsOnly: runForInstallBuildsOnly,
            shellPath: shellPath
        )
    }

    /// Returns a target script that gets executed after the sources and resources build phase.
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
    ///   - runForInstallBuildsOnly: Whether this script only runs on install builds (default is false)
    ///   - shellPath: The path to the shell which shall execute this script. Default is `/bin/sh`.
    /// - Returns: Target script.
    public static func post(
        tool: String,
        arguments: [String],
        name: String,
        inputPaths: [Path] = [],
        inputFileListPaths: [Path] = [],
        outputPaths: [Path] = [],
        outputFileListPaths: [Path] = [],
        basedOnDependencyAnalysis: Bool? = nil,
        runForInstallBuildsOnly: Bool = false,
        shellPath: String = "/bin/sh"
    ) -> TargetScript {
        TargetScript(
            name: name,
            script: .tool(path: tool, args: arguments),
            order: .post,
            inputPaths: inputPaths,
            inputFileListPaths: inputFileListPaths,
            outputPaths: outputPaths,
            outputFileListPaths: outputFileListPaths,
            basedOnDependencyAnalysis: basedOnDependencyAnalysis,
            runForInstallBuildsOnly: runForInstallBuildsOnly,
            shellPath: shellPath
        )
    }

    // MARK: Embedded script init

    /// Returns a target script that gets executed before the sources and resources build phase.
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
    ///   - runForInstallBuildsOnly: Whether this script only runs on install builds (default is false)
    ///   - shellPath: The path to the shell which shall execute this script. Default is `/bin/sh`.
    /// - Returns: Target script.
    public static func pre(
        script: String,
        name: String,
        inputPaths: [Path] = [],
        inputFileListPaths: [Path] = [],
        outputPaths: [Path] = [],
        outputFileListPaths: [Path] = [],
        basedOnDependencyAnalysis: Bool? = nil,
        runForInstallBuildsOnly: Bool = false,
        shellPath: String = "/bin/sh"
    ) -> TargetScript {
        TargetScript(
            name: name,
            script: .embedded(script),
            order: .pre,
            inputPaths: inputPaths,
            inputFileListPaths: inputFileListPaths,
            outputPaths: outputPaths,
            outputFileListPaths: outputFileListPaths,
            basedOnDependencyAnalysis: basedOnDependencyAnalysis,
            runForInstallBuildsOnly: runForInstallBuildsOnly,
            shellPath: shellPath
        )
    }

    /// Returns a target script that gets executed after the sources and resources build phase.
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
    ///   - runForInstallBuildsOnly: Whether this script only runs on install builds (default is false)
    ///   - shellPath: The path to the shell which shall execute this script. Default is `/bin/sh`.
    /// - Returns: Target script.
    public static func post(
        script: String,
        name: String,
        inputPaths: [Path] = [],
        inputFileListPaths: [Path] = [],
        outputPaths: [Path] = [],
        outputFileListPaths: [Path] = [],
        basedOnDependencyAnalysis: Bool? = nil,
        runForInstallBuildsOnly: Bool = false,
        shellPath: String = "/bin/sh"
    ) -> TargetScript {
        TargetScript(
            name: name,
            script: .embedded(script),
            order: .post,
            inputPaths: inputPaths,
            inputFileListPaths: inputFileListPaths,
            outputPaths: outputPaths,
            outputFileListPaths: outputFileListPaths,
            basedOnDependencyAnalysis: basedOnDependencyAnalysis,
            runForInstallBuildsOnly: runForInstallBuildsOnly,
            shellPath: shellPath
        )
    }
}
