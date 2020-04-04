import Basic
import Foundation
import SPMUtility
import TuistCore
import TuistSigning
import TuistSupport

class DecryptCommand: NSObject, Command {
    // MARK: - Attributes

    static let command = "decrypt"
    static let overview = "Decrypts all files in Tuist/Signing directory."
    private let pathArgument: OptionArgument<String>
    private let keepFilesArgument: OptionArgument<Bool>

    private let signingCipher: SigningCiphering

    // MARK: - Init

    public required convenience init(parser: ArgumentParser) {
        self.init(parser: parser, signingCipher: SigningCipher())
    }

    init(parser: ArgumentParser,
         signingCipher: SigningCiphering) {
        let subParser = parser.add(subparser: DecryptCommand.command, overview: DecryptCommand.overview)
        pathArgument = subParser.add(option: "--path",
                                     shortName: "-p",
                                     kind: String.self,
                                     usage: "The path to the folder containing the encrypted certificates",
                                     completion: .filename)
        keepFilesArgument = subParser.add(option: "--keep-files",
                                           shortName: "-k",
                                           kind: Bool.self,
                                           usage: "Should keep encrypted files after decryption",
                                           completion: nil)
        self.signingCipher = signingCipher
    }

    func run(with arguments: ArgumentParser.Result) throws {
        let path = self.path(arguments: arguments)
        let keepFiles = arguments.get(keepFilesArgument) ?? false
        try signingCipher.decryptSigning(at: path, keepFiles: keepFiles)
        logger.notice("Successfully decrypted all signing files", metadata: .success)
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
