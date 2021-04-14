import ArgumentParser
import Foundation
import TSCBasic

struct EncryptCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "encrypt",
            _superCommandName: "signing",
            abstract: "Encrypts all files in Tuist/Signing directory"
        )
    }

    @Option(
        name: .shortAndLong,
        help: "The path to the folder containing the certificates you would like to encrypt",
        completion: .directory
    )
    var path: String?

    func run() throws {
        try EncryptService().run(path: path)
    }
}
