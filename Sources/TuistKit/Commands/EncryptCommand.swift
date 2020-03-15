import Basic
import Foundation
import SPMUtility
import TuistCore
import TuistSupport
import TuistSigning

class EncryptCommand: NSObject, Command {
    // MARK: - Attributes

    static let command = "encrypt"
    static let overview = "Encrypts all files in Tuist/Signing directory."
    
    private let signingCipher: SigningCiphering

    // MARK: - Init

    public required convenience init(parser: ArgumentParser) {
        self.init(parser: parser, signingCipher: SigningCipher())
    }

    init(parser: ArgumentParser,
         signingCipher: SigningCiphering) {
        _ = parser.add(subparser: EncryptCommand.command, overview: EncryptCommand.overview)
        self.signingCipher = signingCipher
    }
    
    func run(with arguments: ArgumentParser.Result) throws {
        try signingCipher.encryptSigning(at: FileHandler.shared.currentPath)
    }
}
