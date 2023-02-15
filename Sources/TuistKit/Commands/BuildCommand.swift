import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

/// Command that builds a target from the project in the current directory.
struct BuildCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "build",
            abstract: "Builds a project"
        )
    }

    @Argument(
        help: "The scheme to be built. By default it builds all the buildable schemes of the project in the current directory."
    )
    var scheme: String?

    @Flag(
        help: "Force the generation of the project before building."
    )
    var generate: Bool = false

    @Flag(
        help: "When passed, it cleans the project before building it"
    )
    var clean: Bool = false

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project to be built.",
        completion: .directory
    )
    var path: String?

    @Option(
        name: .shortAndLong,
        help: "Build on a specific device."
    )
    var device: String?

    @Option(
        name: .shortAndLong,
        help: "Build with a specific version of the OS."
    )
    var os: String?

    @Option(
        name: [.long, .customShort("C")],
        help: "The configuration to be used when building the scheme."
    )
    var configuration: String?

    @Option(
        help: "The directory where build products will be copied to when the project is built.",
        completion: .directory
    )
    var buildOutputPath: String?

    func run() async throws {
        let absolutePath: AbsolutePath
        if let path = path {
            absolutePath = try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            absolutePath = FileHandler.shared.currentPath
        }

        try await BuildService().run(
            schemeName: scheme,
            generate: generate,
            clean: clean,
            configuration: configuration,
            buildOutputPath: buildOutputPath.map { try AbsolutePath(validating: $0, relativeTo: FileHandler.shared.currentPath) },
            path: absolutePath,
            device: device,
            osVersion: os
        )
    }
}
