import ArgumentParser
import Foundation
import TSCBasic
import TuistCore
import TuistSigning
import TuistSupport

public struct DecryptCommand: ParsableCommand {
    // MARK: - Configuration

    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "decrypt",
            _superCommandName: "signing",
            abstract: "Decrypts all files in Tuist/Signing directory"
        )
    }

    // MARK: - Arguments and Flags

    @Option(
        name: .shortAndLong,
        help: "The path to the folder containing the encrypted certificates",
        completion: .directory
    )
    var path: String?

    // MARK: - Init

    public init() {}

    // MARK: - ParsableCommand

    public func run() throws {
        try DecryptService().run(path: path)
    }
}
