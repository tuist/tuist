import ArgumentParser
import Foundation
import TuistEnvKey

enum Runnable: ExpressibleByArgument, Equatable {
    init?(argument: String) {
        let specifierComponents = argument.components(separatedBy: "@")
        if argument.starts(with: "http://") || argument.starts(with: "https://"),
           let previewLink = URL(string: argument)
        {
            self = .url(previewLink)
        } else if specifierComponents.count == 2 {
            self = .specifier(displayName: specifierComponents[0], specifier: specifierComponents[1])
        } else {
            self = .scheme(argument)
        }
    }

    case url(Foundation.URL)
    case scheme(String)
    case specifier(displayName: String, specifier: String)
}

public struct RunCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "run",
            abstract: "Runs a preview or a scheme from a generated project.",
            discussion: RunCommand.discussionText
        )
    }

    @Argument(
        help: ArgumentHelp(RunCommand.runnableHelp),
        envKey: .runScheme
    )
    var runnable: Runnable

    #if os(macOS)
        private static let runnableHelp =
            "A preview URL, app name with a specifier such as App@latest or App@feature-branch, or a scheme from a generated project."
        private static let discussionText =
            "Run a preview by passing a preview URL or an app specifier (e.g. App@latest). You can also run a scheme from a Tuist-generated project."
    #else
        private static let runnableHelp =
            "A preview URL or app name with a specifier such as App@latest or App@feature-branch."
        private static let discussionText =
            "Run a preview by passing a preview URL or an app specifier (e.g. App@latest)."
    #endif

    @Option(
        name: .shortAndLong,
        help: "The path to the directory that contains the project with the target or scheme to be run.",
        completion: .directory
    )
    var path: String?

    @Option(help: "The device name to run on.")
    var device: String?

    #if os(macOS)
        @Flag(
            help: "Force the generation of the project before running.",
            envKey: .runGenerate
        )
        var generate: Bool = false

        @Flag(
            help: "When passed, it cleans the project before running.",
            envKey: .runClean
        )
        var clean: Bool = false

        @Option(
            name: [.long, .customShort("C")],
            help: "The configuration to be used when building the scheme."
        )
        var configuration: String?

        @Option(
            name: .shortAndLong,
            help: "The OS version of the simulator.",
            envKey: .runOS
        )
        var os: String?

        @Flag(
            name: .long,
            help: "When passed, append arch=x86_64 to the 'destination' to run simulator in a Rosetta mode."
        )
        var rosetta: Bool = false

        @Argument(
            parsing: .captureForPassthrough,
            help: "Arguments to pass to the application during execution. All arguments after the scheme name are forwarded to the app. Example: tuist run MyApp --verbose --config debug",
            envKey: .runArguments
        )
        var arguments: [String] = []
    #endif

    public func run() async throws {
        #if os(macOS)
            try await RunCommandService().run(
                path: path,
                runnable: runnable,
                generate: generate,
                clean: clean,
                configuration: configuration,
                device: device,
                osVersion: os,
                rosetta: rosetta,
                arguments: arguments
            )
        #else
            try await RunCommandService().run(
                path: path,
                runnable: runnable,
                device: device
            )
        #endif
    }
}
