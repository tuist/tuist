import Foundation
import TSCBasic
import TuistCore
import TuistSupport

extension LintingIssue {
    static func noFileExtension(_ path: AbsolutePath) -> Self {
        Self(reason: "Unable to parse extension from file at \(path.pathString)", severity: .error)
    }

    static func expiredProvisioningProfile(_ profile: ProvisioningProfile) -> Self {
        Self(reason: "The provisioning profile \(profile.name) has expired", severity: .warning)
    }

//    static func revokedCertificate(_ certificate: Certificate) -> Self {
//        Self(reason: "The certificate has been revoked \(certificate.name)", severity: .warning)
//    }
//
//    static func provisioningProfilePathNotFound(_ profile: ProvisioningProfile) -> Self {
//        Self(reason: "Could not find any path for \(profile.name)", severity: .warning)
//    }
}

/// Handles installing for signing (provisioning profiles, certificates ...)
protocol SigningInstalling {
    func installProvisioningProfile(_ provisioningProfile: ProvisioningProfile) throws -> [LintingIssue]
    /// Installs certificate to a given keychain
    /// - Parameters:
    ///     - certificate: Certificate to be installed
    ///     - keychainPath: Path to keychain where the certificate should be installed to
    func installCertificate(_ certificate: Certificate, keychainPath: AbsolutePath) throws
}

final class SigningInstaller: SigningInstalling {
    private let securityController: SecurityControlling

    init(securityController: SecurityControlling = SecurityController()) {
        self.securityController = securityController
    }

    func installProvisioningProfile(_ provisioningProfile: ProvisioningProfile) throws -> [LintingIssue] {
        var issues = [LintingIssue]()

        if provisioningProfile.expirationDate < Date() {
            issues.append(.expiredProvisioningProfile(provisioningProfile))
            return issues
        }

        let provisioningProfilesPath = FileHandler.shared.homeDirectory.appending(RelativePath("Library/MobileDevice/Provisioning Profiles"))
        if !FileHandler.shared.exists(provisioningProfilesPath) {
            try FileHandler.shared.createFolder(provisioningProfilesPath)
        }
        let provisioningProfileSourcePath = provisioningProfile.path
        guard
            let profileExtension = provisioningProfileSourcePath.extension
        else {
            issues.append(.noFileExtension(provisioningProfileSourcePath))
            return issues
        }

        let provisioningProfilePath = provisioningProfilesPath.appending(component: provisioningProfile.uuid + "." + profileExtension)
        if FileHandler.shared.exists(provisioningProfilePath) {
            try FileHandler.shared.delete(provisioningProfilePath)
        }
        try FileHandler.shared.copy(
            from: provisioningProfileSourcePath,
            to: provisioningProfilePath
        )

        logger.debug("Installed provisioning profile \(provisioningProfileSourcePath.pathString) to \(provisioningProfilePath.pathString)")
        
        return issues
    }

    func installCertificate(_ certificate: Certificate, keychainPath: AbsolutePath) throws {
        try securityController.importCertificate(certificate, keychainPath: keychainPath)
        logger.debug("Installed certificate with public key at \(certificate.publicKey.pathString) and private key at \(certificate.privateKey.pathString) to keychain at \(keychainPath.pathString)")
    }
}
