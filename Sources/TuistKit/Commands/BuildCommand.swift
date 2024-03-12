import ArgumentParser
import Foundation
import TSCBasic
import TSCUtility
import TuistSupport

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
        help: "When passed, it cleans the project before building it"
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
        help: "Build on a specific device."
    )
    public var device: String?

    @Option(
        name: .long,
        help: "Build for a specific platform."
    )
    public var platform: String?

    @Option(
        name: .shortAndLong,
        help: "Build with a specific version of the OS."
    )
    public var os: String?

    @Flag(
        name: .long,
        help: "When passed, append arch=x86_64 to the 'destination' to run simulator in a Rosetta mode."
    )
    public var rosetta: Bool = false

    @Option(
        name: [.long, .customShort("C")],
        help: "The configuration to be used when building the scheme."
    )
    public var configuration: String?

    @Option(
        help: "The directory where build products will be copied to when the project is built.",
        completion: .directory
    )
    public var buildOutputPath: String?

    @Option(
        help: "Overrides the folder that should be used for derived data when building the project."
    )
    public var derivedDataPath: String?

    @Flag(
        name: .long,
        help: "When passed, it generates the project and skips building. This is useful for debugging purposes."
    )
    public var generateOnly: Bool = false
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
        let absolutePath: AbsolutePath
        if let path = buildOptions.path {
            absolutePath = try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            absolutePath = FileHandler.shared.currentPath
        }

        try await BuildService().run(
            schemeName: buildOptions.scheme,
            generate: buildOptions.generate,
            clean: buildOptions.clean,
            configuration: buildOptions.configuration,
            buildOutputPath: buildOptions.buildOutputPath.map { try AbsolutePath(validating: $0, relativeTo: FileHandler.shared.currentPath) },
            derivedDataPath: buildOptions.derivedDataPath,
            path: absolutePath,
            device: buildOptions.device,
            platform: buildOptions.platform,
            osVersion: buildOptions.os,
            rosetta: buildOptions.rosetta,
            generateOnly: buildOptions.generateOnly
        )
    }
}
