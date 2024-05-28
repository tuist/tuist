import ArgumentParser
import Foundation
import TSCBasic
import TuistGenerator
import TuistSupport

public struct EditCommand: AsyncParsableCommand {
    public init() {}

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "edit",
            abstract: "Generates a temporary project to edit the project in the current directory"
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the directory whose project will be edited",
        completion: .directory,
        envKey: .editPath
    )
    var path: String?

    @Flag(
        name: [.long, .customShort("P")],
        help: "It creates the project in the current directory or the one indicated by -p and doesn't block the process",
        envKey: .editPermanent
    )
    var permanent: Bool = false

    @Flag(
        name: [.long, .customShort("o")],
        help: "It only includes the manifest in the current directory.",
        envKey: .editOnlyCurrentDirectory
    )
    var onlyCurrentDirectory: Bool = false

    public func run() async throws {
        try await EditService().run(
            path: path,
            permanent: permanent,
            onlyCurrentDirectory: onlyCurrentDirectory
        )
    }
}
