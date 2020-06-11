import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

/// Command that builds a target from the project in the current directory.
struct BuildCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "build",
                             abstract: "Builds a project")
    }

    @Argument(
        help: "The scheme to be built. By default it builds all the buildable schemes of the project in the current directory."
    )
    var scheme: String?

    @Flag(
        help: "Force the generation of the project before building."
    )
    var generate: Bool

    @Flag(
        help: "When passed, it cleans the project before building it"
    )
    var clean: Bool

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project to be built."
    )
    var path: String?

    @Option(name: [.long, .customShort("C")],
            help: "The configuration to be used when building the scheme.")
    var configuration: String?

    func run() throws {
        let absolutePath: AbsolutePath
        if let path = path {
            absolutePath = AbsolutePath(path)
        } else {
            absolutePath = FileHandler.shared.currentPath
        }
        try BuildService().run(schemeName: scheme,
                               generate: generate,
                               clean: clean,
                               configuration: configuration,
                               path: absolutePath)
    }
}
