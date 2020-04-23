import TSCBasic
import Foundation
import TuistSupport

enum SigningInstallerError: FatalError, Equatable {
    case invalidProvisioningProfile(AbsolutePath)
    case noFileExtension(AbsolutePath)
    case revokedCertificate(Certificate)
    case expiredProvisioningProfile(ProvisioningProfile)

    var type: ErrorType {
        switch self {
        case .invalidProvisioningProfile, .noFileExtension, .revokedCertificate, .expiredProvisioningProfile:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .invalidProvisioningProfile(path):
            return "Provisioning profile at \(path.pathString) is invalid - check if it has the expected structure"
        case let .noFileExtension(path):
            return "Unable to parse extension from file at \(path.pathString)"
        case let .revokedCertificate(certificate):
            return "Certificate has been revoked \(certificate.name)"
        case let .expiredProvisioningProfile(provisioningProfile):
            return "Provisioning profile \(provisioningProfile.name) has expired"
        }
    }
}

protocol SigningInstalling {
    func installProvisioningProfile(_ provisioningProfile: ProvisioningProfile) throws
    func installCertificate(_ certificate: Certificate, keychainPath: AbsolutePath) throws
}

enum SigningFile {
    case provisioningProfile(AbsolutePath)
    case signingCertificate(AbsolutePath)
}

final class SigningInstaller: SigningInstalling {
    private let securityController: SecurityControlling

    init(securityController: SecurityControlling = SecurityController()) {
        self.securityController = securityController
    }

    func installProvisioningProfile(_ provisioningProfile: ProvisioningProfile) throws {
        guard provisioningProfile.expirationDate < Date() else { throw SigningInstallerError.expiredProvisioningProfile(provisioningProfile) }
        let provisioningProfilesPath = FileHandler.shared.homeDirectory.appending(RelativePath("Library/MobileDevice/Provisioning Profiles"))
        if !FileHandler.shared.exists(provisioningProfilesPath) {
            try FileHandler.shared.createFolder(provisioningProfilesPath)
        }
        guard let profileExtension = provisioningProfile.path.extension else { throw SigningInstallerError.noFileExtension(provisioningProfile.path) }
        
        let provisioningProfilePath = provisioningProfilesPath.appending(component: provisioningProfile.uuid + "." + profileExtension)
        if FileHandler.shared.exists(provisioningProfilePath) {
            try FileHandler.shared.delete(provisioningProfilePath)
        }
        try FileHandler.shared.copy(from: provisioningProfile.path,
                                    to: provisioningProfilePath)

        logger.debug("Installed provisioning profile \(provisioningProfile.path.pathString) to \(provisioningProfilePath.pathString)")
    }

    func installCertificate(_ certificate: Certificate, keychainPath: AbsolutePath) throws {
        try securityController.importCertificate(certificate, keychainPath: keychainPath)
    }
}
