import AnyCodable
import ArgumentParser
import Foundation
import TuistCore

public struct GenerateCommand: AsyncParsableCommand, HasTrackableParameters {
    public init() {}
    public static var analyticsDelegate: TrackableParametersDelegate?

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "generate",
            abstract: "Generates an Xcode workspace to start working on the project.",
            subcommands: []
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory or a subdirectory of the project.",
        completion: .directory
    )
    var path: String?

    @Flag(
        name: .shortAndLong,
        help: "Don't open the project after generating it."
    )
    var noOpen: Bool = false

    public func run() async throws {
        try await GenerateService().run(
            path: path,
            noOpen: noOpen
        )
    }
}
