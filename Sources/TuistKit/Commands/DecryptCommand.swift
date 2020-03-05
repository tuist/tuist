import Basic
import Foundation
import SPMUtility
import TuistCore
import TuistSupport
import TuistSigning

// swiftlint:disable:next type_body_length
class DecryptCommand: NSObject, Command {
    // MARK: - Attributes

    static let command = "decrypt"
    static let overview = "Decrypts all files in Tuist/Signing directory."
    
    private let signingCipher: SigningCiphering

    // MARK: - Init

    public required convenience init(parser: ArgumentParser) {
        self.init(parser: parser, signingCipher: SigningCipher())
    }

    init(parser: ArgumentParser,
         signingCipher: SigningCiphering) {
        _ = parser.add(subparser: DecryptCommand.command, overview: DecryptCommand.overview)
        self.signingCipher = signingCipher
    }
    
    func run(with arguments: ArgumentParser.Result) throws {
        try signingCipher.decryptSigning(at: FileHandler.shared.currentPath)
    }
}
