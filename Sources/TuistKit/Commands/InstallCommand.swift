import Basic
import Foundation
import SPMUtility
import TuistCore
import TuistSigning
import TuistSupport

class InstallCommand: NSObject, Command {
    // MARK: - Attributes

    static let command = "install"
    static let overview = "Installs all profiles/certificates in Tuist/Signing directory to your system."
    private let pathArgument: OptionArgument<String>

    private let signingCipher: SigningCiphering
    private let signingInstaller: SigningInstalling

    // MARK: - Init

    public required convenience init(parser: ArgumentParser) {
        self.init(parser: parser,
                  signingCipher: SigningCipher(),
                  signingInstaller: SigningInstaller())
    }

    init(parser: ArgumentParser,
         signingCipher: SigningCiphering,
         signingInstaller: SigningInstalling) {
        let subParser = parser.add(subparser: InstallCommand.command, overview: InstallCommand.overview)
        pathArgument = subParser.add(option: "--path",
                                     shortName: "-p",
                                     kind: String.self,
                                     usage: "The path to the folder containing the certificates you would like to encrypt",
                                     completion: .filename)
        self.signingCipher = signingCipher
        self.signingInstaller = signingInstaller
    }

    func run(with arguments: ArgumentParser.Result) throws {
        let path = self.path(arguments: arguments)
        // TODO: Decrypt only files without .encrypted extension
//        try signingCipher.decryptSigning(at: path)
        
        try signingInstaller.installSigning(at: path)

        // TODO: Delete decrypted files
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
