import Basic
import Foundation
import SPMUtility
import TuistCore
import TuistSigning
import TuistSupport

class EncryptCommand: NSObject, Command {
    // MARK: - Attributes

    static let command = "encrypt"
    static let overview = "Encrypts all files in Tuist/Signing directory."
    private let pathArgument: OptionArgument<String>
    private let keepFilesArgument: OptionArgument<Bool>

    private let signingCipher: SigningCiphering

    // MARK: - Init

    public required convenience init(parser: ArgumentParser) {
        self.init(parser: parser, signingCipher: SigningCipher())
    }

    init(parser: ArgumentParser,
         signingCipher: SigningCiphering) {
        let subParser = parser.add(subparser: EncryptCommand.command, overview: EncryptCommand.overview)
        pathArgument = subParser.add(option: "--path",
                                     shortName: "-p",
                                     kind: String.self,
                                     usage: "The path to the folder containing the certificates you would like to encrypt",
                                     completion: .filename)
        keepFilesArgument = subParser.add(option: "--keep-files",
                                          shortName: "-k",
                                          kind: Bool.self,
                                          usage: "Should keep unencrypted files after encryption",
                                          completion: nil)
        self.signingCipher = signingCipher
    }

    func run(with arguments: ArgumentParser.Result) throws {
        let path = self.path(arguments: arguments)
        let keepFiles = arguments.get(keepFilesArgument) ?? false
        try signingCipher.encryptSigning(at: path, keepFiles: keepFiles)

        logger.notice("Successfully encrypted all signing files", metadata: .success)
    }

    // MARK: - Helpers

    private func path(arguments: ArgumentParser.Result) -> AbsolutePath {
        if let path = arguments.get(pathArgument) {
            return AbsolutePath(path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }
}
