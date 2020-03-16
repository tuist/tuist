import Basic
import Foundation
import SPMUtility
import TuistCore
import TuistSupport
import TuistSigning

class SigningCommand: NSObject, Command {    
    // MARK: - Attributes

    static let command = "signing"
    static let overview = "Signing command"
    let subcommands: [Command]
    
    private let argumentParser: ArgumentParser
    private let signingCipher: SigningCiphering

    // MARK: - Init

    public required convenience init(parser: ArgumentParser) {
        self.init(parser: parser, signingCipher: SigningCipher())
    }

    init(parser: ArgumentParser,
         signingCipher: SigningCiphering) {
        _ = parser.add(subparser: SigningCommand.command, overview: SigningCommand.overview)
        let argumentParser = ArgumentParser(commandName: Self.command, usage: "tuist signing <command> <options>", overview: Self.overview)
        let subcommands: [Command.Type] = [EncryptCommand.self, DecryptCommand.self]
        self.subcommands = subcommands.map { $0.init(parser: argumentParser) }
        self.argumentParser = argumentParser
        self.signingCipher = signingCipher
    }
    
    func parse(with parser: ArgumentParser, arguments: [String]) throws -> (ArgumentParser.Result, ArgumentParser) {
        return (try argumentParser.parse(Array(arguments.dropFirst())), argumentParser)
    }
    
    func run(with arguments: ArgumentParser.Result) throws {
        argumentParser.printUsage(on: stdoutStream)
    }
}
