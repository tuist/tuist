import TSCBasic
import Foundation
import TuistSupport

enum SigningInstallerError: FatalError, Equatable {
    case invalidProvisioningProfile(AbsolutePath)
    case noFileExtension(AbsolutePath)

    var type: ErrorType {
        switch self {
        case .invalidProvisioningProfile, .noFileExtension:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .invalidProvisioningProfile(path):
            return "Provisioning profile at \(path.pathString) is invalid - check if it has the expected structure"
        case let .noFileExtension(path):
            return "Unable to parse extension from file at \(path.pathString)"
        }
    }
}

protocol SigningInstalling {
    func installProvisioningProfile(_ provisioningProfile: ProvisioningProfile) throws
    func installCertificate(at path: AbsolutePath) throws
}

enum SigningFile {
    case provisioningProfile(AbsolutePath)
    case signingCertificate(AbsolutePath)
}

final class SigningInstaller: SigningInstalling {
    private let signingFilesLocator: SigningFilesLocating
    private let signingCipher: SigningCiphering
    private let securityController: SecurityControlling

    public convenience init() {
        self.init(signingFilesLocator: SigningFilesLocator(),
                  signingCipher: SigningCipher(),
                  securityController: SecurityController())
    }

    init(signingFilesLocator: SigningFilesLocating,
         signingCipher: SigningCiphering,
         securityController: SecurityControlling) {
        self.signingFilesLocator = signingFilesLocator
        self.signingCipher = signingCipher
        self.securityController = securityController
    }

//    public func installSigning(at path: AbsolutePath) throws {
//        guard (try? signingFilesLocator.hasSigningDirectory(at: path)) ?? false else { return }
//        try signingCipher.decryptSigning(at: path, keepFiles: true)
//        let signingKeyFiles = try signingFilesLocator.locateUnencryptedSigningFiles(at: path)
//        try signingKeyFiles.forEach {
//            switch $0.extension {
//            case "mobileprovision", "provisionprofile":
//                try installProvisioningProfile(at: $0)
//            case "cer":
//                try importCertificate(at: $0)
//            default:
//                logger.warning("File \($0.pathString) has unknown extension")
//            }
//        }
//        try signingCipher.encryptSigning(at: path)
//    }

    func installProvisioningProfile(_ provisioningProfile: ProvisioningProfile) throws {
//        let unencryptedProvisioningProfile = try securityController.decodeFile(at: path)
//        let xmlDocument = try AEXMLDocument(xml: unencryptedProvisioningProfile)
//        let children = xmlDocument.root.children.flatMap { $0.children }
//
//        guard let profileExtension = path.extension else { throw SigningInstallerError.noFileExtension(path) }

//        guard
//            let uuidIndex = children.firstIndex(where: { $0.string == "UUID" }),
//            children.index(after: uuidIndex) != children.endIndex,
//            let uuid = children[children.index(after: uuidIndex)].value
//        else { throw SigningInstallerError.invalidProvisioningProfile(path) }
//
//        let provisioningProfilesPath = FileHandler.shared.homeDirectory.appending(RelativePath("Library/MobileDevice/Provisioning Profiles"))
//        if !FileHandler.shared.exists(provisioningProfilesPath) {
//            try FileHandler.shared.createFolder(provisioningProfilesPath)
//        }
//        let encryptedProvisioningProfile = try FileHandler.shared.readFile(path)
//        let provisioningProfilePath = provisioningProfilesPath.appending(component: uuid + "." + profileExtension)
//        try encryptedProvisioningProfile.write(to: provisioningProfilePath.url)
//
//        logger.debug("Installed provisioning profile \(path.pathString) to \(provisioningProfilePath.pathString)")
    }

    func installCertificate(at path: AbsolutePath) throws {
//        try securityController.importCertificate(at: path)
    }
}
