import ArgumentParser
import Foundation
import TSCBasic
import TSCUtility
import TuistSupport

enum BuildCommandError: FatalError, Equatable {
    case passthroughArgumentAlreadyHandled(String)

    var description: String {
        switch self {
        case let .passthroughArgumentAlreadyHandled(argument):
            "The argument \(argument) added after the terminator (--) cannot be passthrough to xcodebuild because it is handled by tuist"
        }
    }

    var type: ErrorType {
        switch self {
        case .passthroughArgumentAlreadyHandled:
            .abort
        }
    }
}

public struct BuildOptions: ParsableArguments {
    public init() {}

    @Argument(
        help: "The scheme to be built. By default it builds all the buildable schemes of the project in the current directory."
    )
    public var scheme: String?

    @Flag(
        help: "Force the generation of the project before building."
    )
    public var generate: Bool = false

    @Flag(
        help: "[Deprecated] When passed, it cleans the project before building it"
    )
    public var clean: Bool = false

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project to be built.",
        completion: .directory
    )
    public var path: String?

    @Option(
        name: .shortAndLong,
        help: "[Deprecated] Build on a specific device."
    )
    public var device: String?

    @Option(
        name: .long,
        help: "[Deprecated] Build for a specific platform."
    )
    public var platform: String?

    @Option(
        name: .shortAndLong,
        help: "[Deprecated] Build with a specific version of the OS."
    )
    public var os: String?

    @Flag(
        name: .long,
        help: "[Deprecated] When passed, append arch=x86_64 to the 'destination' to run simulator in a Rosetta mode."
    )
    public var rosetta: Bool = false

    @Option(
        name: [.long, .customShort("C")],
        help: "[Deprecated] The configuration to be used when building the scheme."
    )
    public var configuration: String?

    @Option(
        help: "The directory where build products will be copied to when the project is built.",
        completion: .directory
    )
    public var buildOutputPath: String?

    @Option(
        help: "[Deprecated] Overrides the folder that should be used for derived data when building the project."
    )
    public var derivedDataPath: String?

    @Flag(
        name: .long,
        help: "When passed, it generates the project and skips building. This is useful for debugging purposes."
    )
    public var generateOnly: Bool = false
    
    @Argument(
        parsing: .postTerminator,
        help: "xcodebuild arguments that will be passthrough"
    )
    var passthroughXcodeBuildArguments: [String] = []
}

/// Command that builds a target from the project in the current directory.
public struct BuildCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "build",
            abstract: "Builds a project"
        )
    }

    @OptionGroup()
    var buildOptions: BuildOptions

    public func run() async throws {
        // Check if passthrough arguments are already handled by tuist
        if buildOptions.passthroughXcodeBuildArguments.contains("-scheme") {
            throw BuildCommandError.passthroughArgumentAlreadyHandled("-scheme")
        }
        if buildOptions.passthroughXcodeBuildArguments.contains("-workspace") {
            throw BuildCommandError.passthroughArgumentAlreadyHandled("-workspace")
        }
        if buildOptions.passthroughXcodeBuildArguments.contains("-project") {
            throw BuildCommandError.passthroughArgumentAlreadyHandled("-project")
        }

        // Suggest the user to use passthrough arguments if already supported by xcodebuild
        if buildOptions.platform != nil || buildOptions.os != nil || buildOptions.device != nil || buildOptions.rosetta {
            logger.warning("--platform, --os, --device, and --rosetta are deprecated please use -destination DESTINATION after the terminator (--) instead to passthrough parameters to xcodebuild")
        }
        if let configuration = buildOptions.configuration {
            logger.warning("--configuration is deprecated please use -configuration \(configuration) after the terminator (--) instead to passthrough parameters to xcodebuild")
        }
        if buildOptions.clean {
            logger.warning("--clean is deprecated please use clean after the terminator (--) instead to passthrough parameters to xcodebuild")
        }
        if let derivedDataPath = buildOptions.derivedDataPath {
            logger.warning("--derivedDataPath is deprecated please use -derivedDataPath \(derivedDataPath) after the terminator (--) instead to passthrough parameters to xcodebuild")
        }

        let absolutePath = if let path = buildOptions.path {
            try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            FileHandler.shared.currentPath
        }

        try await BuildService().run(
            schemeName: buildOptions.scheme,
            generate: buildOptions.generate,
            clean: buildOptions.clean,
            configuration: buildOptions.configuration,
            buildOutputPath: buildOptions.buildOutputPath.map { try AbsolutePath(
                validating: $0,
                relativeTo: FileHandler.shared.currentPath
            ) },
            derivedDataPath: buildOptions.derivedDataPath,
            path: absolutePath,
            device: buildOptions.device,
            platform: buildOptions.platform,
            osVersion: buildOptions.os,
            rosetta: buildOptions.rosetta,
            generateOnly: buildOptions.generateOnly,
            passthroughXcodeBuildArguments: buildOptions.passthroughXcodeBuildArguments
        )
    }
}
