import ArgumentParser
import Foundation
import TSCBasic
import TuistSupport

struct RunCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "run",
            abstract: "Runs a scheme or target in the project",
            discussion: """
            Given a runnable scheme or target the run command builds & runs it.
            All arguments after the scheme or target are forwarded to the application.
            """
            // TODO: There is a bug in swift-argument-parser dependency (https://github.com/apple/swift-argument-parser/issues/169)
            // add this documentation when this is true
            //
            // For example: calling `tuist run --device iPhone 12 MyScheme Arg1 --arg2 --arg3`
            // Will result in running the application on an iPhone 12 simulator while 'Arg1', '--arg2', and '--arg3' are forwarded to the application.
        )
    }

    @Flag(help: "Force the generation of the project before running.")
    var generate: Bool = false

    @Flag(help: "When passed, it cleans the project before running.")
    var clean: Bool = false

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project with the target or scheme to be run.",
        completion: .directory
    )
    var path: String?

    @Option(
        name: [.long, .customShort("C")],
        help: "The configuration to be used when building the scheme."
    )
    var configuration: String?

    @Option(help: "The simulator device name to run the target or scheme on.")
    var device: String?

    @Option(
        name: .shortAndLong,
        help: "The OS version of the simulator."
    )
    var os: String?

    @Argument(help: "The scheme to be run.")
    var scheme: String

    @Argument(
        parsing: .captureForPassthrough,
        help: "The arguments to pass to the runnable target during execution."
    )
    var arguments: [String] = []

    func run() async throws {
        try await RunService().run(
            path: path,
            schemeName: scheme,
            generate: generate,
            clean: clean,
            configuration: configuration,
            device: device,
            version: os,
            arguments: arguments
        )
    }
}
