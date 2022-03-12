import Foundation
import TSCBasic
import TuistCore

typealias Fingerprint = String
typealias TargetName = String
typealias ConfigurationName = String

/// Matching signing artifacts
protocol SigningMatching {
    /// - Returns: Certificates and provisioning profiles matched with their configuration and target
    /// - Warning: Expects certificates and provisioning profiles already decrypted
    func match(from path: AbsolutePath) throws -> (
        certificates: [Fingerprint: Certificate],
        provisioningProfiles: [TargetName: [ConfigurationName: ProvisioningProfile]]
    )
}

final class SigningMatcher: SigningMatching {
    private let signingFilesLocator: SigningFilesLocating
    private let provisioningProfileParser: ProvisioningProfileParsing
    private let certificateParser: CertificateParsing

    init(
        signingFilesLocator: SigningFilesLocating = SigningFilesLocator(),
        provisioningProfileParser: ProvisioningProfileParsing = ProvisioningProfileParser(),
        certificateParser: CertificateParsing = CertificateParser()
    ) {
        self.signingFilesLocator = signingFilesLocator
        self.provisioningProfileParser = provisioningProfileParser
        self.certificateParser = certificateParser
    }

    func match(from path: AbsolutePath) throws -> (
        certificates: [Fingerprint: Certificate],
        provisioningProfiles: [TargetName: [ConfigurationName: ProvisioningProfile]]
    ) {
        let certificateFiles = try signingFilesLocator.locateUnencryptedCertificates(from: path)
            .sorted()
        let privateKeyFiles = try signingFilesLocator.locateUnencryptedPrivateKeys(from: path)
            .sorted()
        let certificates: [Fingerprint: Certificate] = try zip(certificateFiles, privateKeyFiles)
            .map(certificateParser.parse)
            .reduce(into: [:]) { dict, certificate in
                dict[certificate.fingerprint] = certificate
            }

        let provisioningProfiles: [TargetName: [ConfigurationName: ProvisioningProfile]] = try signingFilesLocator
            .locateProvisioningProfiles(from: path)
            .map(provisioningProfileParser.parse)
            .reduce(into: [:]) { dict, profile in
                var currentTargetDict = dict[profile.targetName] ?? [:]
                currentTargetDict[profile.configurationName] = profile
                dict[profile.targetName] = currentTargetDict
            }

        return (certificates: certificates, provisioningProfiles: provisioningProfiles)
    }
}
