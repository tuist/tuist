import ArgumentParser
import Foundation
import Path
import TSCUtility
import TuistServer
import TuistSupport
import XcodeGraph

enum XcodeBuildPassthroughArgumentError: FatalError, Equatable {
    case alreadyHandled(String)

    var description: String {
        switch self {
        case let .alreadyHandled(argument):
            "The argument \(argument) added after the terminator (--) cannot be passed through to xcodebuild because it is handled by Tuist."
        }
    }

    var type: ErrorType {
        switch self {
        case .alreadyHandled:
            .abort
        }
    }
}

public struct BuildOptions: ParsableArguments {
    public init() {}

    public static var generatorFactory: GeneratorFactorying = GeneratorFactory()
    public static var cacheStorageFactory: CacheStorageFactorying = EmptyCacheStorageFactory()

    @Argument(
        help: "The scheme to be built. By default it builds all the buildable schemes of the project in the current directory.",
        envKey: .buildOptionsScheme
    )
    public var scheme: String?

    @Flag(
        help: "Force the generation of the project before building.",
        envKey: .buildOptionsGenerate
    )
    public var generate: Bool = false

    @Flag(
        help: "When passed, it cleans the project before building it",
        envKey: .buildOptionsClean
    )
    public var clean: Bool = false

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project to be built.",
        completion: .directory,
        envKey: .buildOptionsPath
    )
    public var path: String?

    @Option(
        name: .shortAndLong,
        help: "Build on a specific device.",
        envKey: .buildOptionsDevice
    )
    public var device: String?

    @Option(
        name: .long,
        help: "Build for a specific platform.",
        envKey: .buildOptionsPlatform
    )
    public var platform: XcodeGraph.Platform?

    @Option(
        name: .shortAndLong,
        help: "Build with a specific version of the OS.",
        envKey: .buildOptionsOS
    )
    public var os: String?

    @Flag(
        name: .long,
        help: "When passed, append arch=x86_64 to the 'destination' to run simulator in a Rosetta mode.",
        envKey: .buildOptionsRosetta
    )
    public var rosetta: Bool = false

    @Option(
        name: [.long, .customShort("C")],
        help: "The configuration to be used when building the scheme.",
        envKey: .buildOptionsConfiguration
    )
    public var configuration: String?

    @Option(
        help: "The directory where build products will be copied to when the project is built.",
        completion: .directory,
        envKey: .buildOptionsOutputPath
    )
    public var buildOutputPath: String?

    @Option(
        help: "[Deprecated] Overrides the folder that should be used for derived data when building the project.",
        envKey: .buildOptionsDerivedDataPath
    )
    public var derivedDataPath: String?

    @Flag(
        name: .long,
        help: "When passed, it generates the project and skips building. This is useful for debugging purposes.",
        envKey: .buildOptionsGenerateOnly
    )
    public var generateOnly: Bool = false

    @Argument(
        parsing: .postTerminator,
        help: "Arguments that will be passed through to xcodebuild",
        envKey: .buildOptionsPassthroughXcodeBuildArguments
    )
    var passthroughXcodeBuildArguments: [String] = []
}

/// Command that builds a target from the project in the current directory.
public struct BuildCommand: AsyncParsableCommand {
    public init() {}
    public static var generatorFactory: GeneratorFactorying = GeneratorFactory()
    public static var cacheStorageFactory: CacheStorageFactorying = EmptyCacheStorageFactory()

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "build",
            abstract: "Builds a project"
        )
    }

    @OptionGroup()
    var buildOptions: BuildOptions

    @Flag(
        help: "Ignore binary cache and use sources only.",
        envKey: .buildBinaryCache
    )
    var binaryCache: Bool = true

    private var notAllowedPassthroughXcodeBuildArguments = [
        "-scheme",
        "-workspace",
        "-project",
    ]

    public func run() async throws {
        // Check if passthrough arguments are already handled by tuist
        try notAllowedPassthroughXcodeBuildArguments.forEach {
            if buildOptions.passthroughXcodeBuildArguments.contains($0) {
                throw XcodeBuildPassthroughArgumentError.alreadyHandled($0)
            }
        }

        // Suggest the user to use passthrough arguments if already supported by xcodebuild
        if let derivedDataPath = buildOptions.derivedDataPath {
            logger
                .warning(
                    "--derivedDataPath is deprecated please use -derivedDataPath \(derivedDataPath) after the terminator (--) instead to passthrough parameters to xcodebuild"
                )
        }

        let absolutePath = if let path = buildOptions.path {
            try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            FileHandler.shared.currentPath
        }

        try await BuildService(
            generatorFactory: Self.generatorFactory,
            cacheStorageFactory: Self.cacheStorageFactory
        ).run(
            schemeName: buildOptions.scheme,
            generate: buildOptions.generate,
            clean: buildOptions.clean,
            configuration: buildOptions.configuration,
            ignoreBinaryCache: !binaryCache,
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

extension XcodeGraph.Platform: ExpressibleByArgument {
    public init?(argument: String) {
        self.init(commandLineValue: argument)
    }
}
