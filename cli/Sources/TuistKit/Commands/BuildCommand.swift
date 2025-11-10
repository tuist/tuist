import ArgumentParser
import Foundation
import Path
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

enum PlatformValidationError: FatalError, Equatable {
    case invalidPlatform(String, availablePlatforms: [String])
    case emptyPlatformList
    case parsingError(String)

    var description: String {
        switch self {
        case let .invalidPlatform(platform, availablePlatforms):
            "Invalid platform '\(platform)'. Supported platforms: \(availablePlatforms.joined(separator: ", "))"
        case .emptyPlatformList:
            "At least one platform must be specified when using --platforms option"
        case let .parsingError(error):
            "Error parsing platforms: \(error)"
        }
    }

    var type: ErrorType {
        switch self {
        case .invalidPlatform, .emptyPlatformList, .parsingError:
            .abort
        }
    }
}

public struct BuildOptions: ParsableArguments {
    public init() {}

    public static var generatorFactory: GeneratorFactorying = GeneratorFactory()
    public static var cacheStorageFactory: CacheStorageFactorying = EmptyCacheStorageFactory()

    @Argument(
        help:
        "The scheme to be built. By default it builds all the buildable schemes of the project in the current directory.",
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
        help: "Build for specific platforms (comma-separated: ios, tvos, macos, watchos, visionos).",
        envKey: .buildOptionsPlatforms
    )
    public var platforms: String?

    @Option(
        name: .shortAndLong,
        help: "Build with a specific version of the OS.",
        envKey: .buildOptionsOS
    )
    public var os: String?

    @Flag(
        name: .long,
        help:
        "When passed, append arch=x86_64 to the 'destination' to run simulator in a Rosetta mode.",
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
        help:
        "[Deprecated] Overrides the folder that should be used for derived data when building the project.",
        envKey: .buildOptionsDerivedDataPath
    )
    public var derivedDataPath: String?

    @Flag(
        name: .long,
        help:
        "When passed, it generates the project and skips building. This is useful for debugging purposes.",
        envKey: .buildOptionsGenerateOnly
    )
    public var generateOnly: Bool = false

    @Argument(
        parsing: .postTerminator,
        help: "Arguments that will be passed through to xcodebuild. Use -- followed by xcodebuild arguments. Example: tuist build -- -destination 'platform=iOS Simulator,name=iPhone 15' -sdk iphonesimulator",
        envKey: .buildOptionsPassthroughXcodeBuildArguments
    )
    var passthroughXcodeBuildArguments: [String] = []
}

/// Command that builds a target from the project in the current directory.
public struct BuildCommand: AsyncParsableCommand, LogConfigurableCommand,
    RecentPathRememberableCommand
{
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "build",
            abstract: "Builds a project"
        )
    }

    var logFilePathDisplayStrategy: LogFilePathDisplayStrategy = .always

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
            Logger.current
                .warning(
                    "--derivedDataPath is deprecated please use -derivedDataPath \(derivedDataPath) after the terminator (--) instead to passthrough parameters to xcodebuild"
                )
        }

        let absolutePath =
            if let path = buildOptions.path {
                try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
            } else {
                FileHandler.shared.currentPath
            }

        // Parse and validate platforms
        let platformList: [XcodeGraph.Platform]
        if let platformsString = buildOptions.platforms {
            do {
                let supportedPlatforms = ["ios", "tvos", "macos", "watchos", "visionos"]
                platformList = try platformsString
                    .split(separator: ",")
                    .map { platformString in
                        let trimmedString = String(platformString.trimmingCharacters(in: .whitespaces))
                        guard let platform = XcodeGraph.Platform(rawValue: trimmedString.lowercased()) else {
                            throw PlatformValidationError.invalidPlatform(trimmedString, availablePlatforms: supportedPlatforms)
                        }
                        return platform
                    }
                
                if platformList.isEmpty {
                    throw PlatformValidationError.emptyPlatformList
                }
                
                // Log platforms that will be built
                let platformNames = platformList.map { $0.rawValue.capitalized }
                Logger.current.log(level: .info, "🎯 Building for platforms: \(platformNames.joined(separator: ", "))")
                
            } catch let error as PlatformValidationError {
                throw error
            } catch {
                throw PlatformValidationError.parsingError(error.localizedDescription)
            }
        } else {
            platformList = [nil].compactMap { $0 } // Default to single build with no specific platform
        }

        // Build for each platform
        if platformList.isEmpty {
            // Default single build without platform specification
            try await BuildService(
                generatorFactory: Extension.generatorFactory,
                cacheStorageFactory: Extension.cacheStorageFactory
            ).run(
                schemeName: buildOptions.scheme,
                generate: buildOptions.generate,
                clean: buildOptions.clean,
                configuration: buildOptions.configuration,
                ignoreBinaryCache: !binaryCache,
                buildOutputPath: buildOptions.buildOutputPath.map {
                    try AbsolutePath(
                        validating: $0,
                        relativeTo: FileHandler.shared.currentPath
                    )
                },
                derivedDataPath: buildOptions.derivedDataPath,
                path: absolutePath,
                device: buildOptions.device,
                platform: nil,
                osVersion: buildOptions.os,
                rosetta: buildOptions.rosetta,
                generateOnly: buildOptions.generateOnly,
                passthroughXcodeBuildArguments: buildOptions.passthroughXcodeBuildArguments
            )
        } else {
            // Multi-platform build
            for (index, platform) in platformList.enumerated() {
                let platformName = platform.rawValue.capitalized
                let progressInfo = platformList.count > 1 ? " (\(index + 1)/\(platformList.count))" : ""
                Logger.current.log(level: .info, "🏗️  Building for \(platformName)\(progressInfo)")
                
                do {
                    try await BuildService(
                        generatorFactory: Extension.generatorFactory,
                        cacheStorageFactory: Extension.cacheStorageFactory
                    ).run(
                        schemeName: buildOptions.scheme,
                        generate: buildOptions.generate,
                        clean: buildOptions.clean,
                        configuration: buildOptions.configuration,
                        ignoreBinaryCache: !binaryCache,
                        buildOutputPath: buildOptions.buildOutputPath.map {
                            try AbsolutePath(
                                validating: $0,
                                relativeTo: FileHandler.shared.currentPath
                            )
                        },
                        derivedDataPath: buildOptions.derivedDataPath,
                        path: absolutePath,
                        device: buildOptions.device,
                        platform: platform,
                        osVersion: buildOptions.os,
                        rosetta: buildOptions.rosetta,
                        generateOnly: buildOptions.generateOnly,
                        passthroughXcodeBuildArguments: buildOptions.passthroughXcodeBuildArguments
                    )
                    Logger.current.log(level: .info, "✅ \(platformName) build completed successfully")
                } catch {
                    Logger.current.log(level: .error, "❌ \(platformName) build failed: \(error.localizedDescription)")
                    throw error
                }
            }
            
            if platformList.count > 1 {
                Logger.current.log(level: .info, "🎉 Successfully built for all \(platformList.count) platforms")
            }
        }
    }
}

extension XcodeGraph.Platform: ArgumentParser.ExpressibleByArgument {
    public init?(argument: String) {
        self.init(commandLineValue: argument)
    }
}