import Basic
import Foundation
import SPMUtility
import TuistCore
import TuistSigning
import TuistSupport

class SigningCommand: NSObject, Command {
    // MARK: - Attributes

    static let command = "signing"
    static let overview = "A set of commands for signing-related operations. "
    let subcommands: [Command]

    private let argumentParser: ArgumentParser

    // MARK: - Init

    public required init(parser: ArgumentParser) {
        _ = parser.add(subparser: SigningCommand.command, overview: SigningCommand.overview)
        let argumentParser = ArgumentParser(commandName: Self.command, usage: "tuist signing <command> <options>", overview: Self.overview)
        let subcommands: [Command.Type] = [EncryptCommand.self, DecryptCommand.self, InstallCommand.self]
        self.subcommands = subcommands.map { $0.init(parser: argumentParser) }
        self.argumentParser = argumentParser
    }

    func parse(with _: ArgumentParser, arguments: [String]) throws -> (ArgumentParser.Result, ArgumentParser) {
        return (try argumentParser.parse(Array(arguments.dropFirst())), argumentParser)
    }

    func run(with _: ArgumentParser.Result) throws {
        argumentParser.printUsage(on: stdoutStream)
    }
}
