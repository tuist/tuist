import Foundation
import TSCBasic
import TuistCore

protocol SigningMatching {
    func match(graph: Graph) throws ->
    (certificates: [String: Certificate],
    provisioningProfiles: [String: [String: ProvisioningProfile]])
}

final class SigningMatcher: SigningMatching {
    private let signingFilesLocator: SigningFilesLocating
    private let signingCipher: SigningCiphering
    private let provisioningProfileParser: ProvisioningProfileParsing
    private let certificateParser: CertificateParsing
    
    init(signingFilesLocator: SigningFilesLocating = SigningFilesLocator(),
         signingCipher: SigningCiphering = SigningCipher(),
         provisioningProfileParser: ProvisioningProfileParsing = ProvisioningProfileParser(),
         certificateParser: CertificateParsing = CertificateParser()) {
        self.signingFilesLocator = signingFilesLocator
        self.signingCipher = signingCipher
        self.provisioningProfileParser = provisioningProfileParser
        self.certificateParser = certificateParser
    }
    
    func match(graph: Graph) throws ->
        (certificates: [String: Certificate],
        provisioningProfiles: [String: [String: ProvisioningProfile]]) {
        let entryPath = graph.entryPath
        
        try signingCipher.decryptSigning(at: entryPath, keepFiles: true)
        defer { try? signingCipher.encryptSigning(at: entryPath, keepFiles: false) }
        
        let certificateFiles = try signingFilesLocator.locateUnencryptedCertificates(at: entryPath)
            .sorted()
        let privateKeyFiles = try signingFilesLocator.locateUnencryptedPrivateKeys(at: entryPath)
            .sorted()
        let certificates = try zip(certificateFiles, privateKeyFiles)
            .map(certificateParser.parse)
            .reduce(into: [:]) { dict, certificate in
                dict[certificate.publicKey.basenameWithoutExt] = certificate
            }
        
        // Dictionary of [ProvisioningProfile.targetName: [ProvisioningProfile.configurationName: ProvisioningProfile]]
        let provisioningProfiles: [String: [String: ProvisioningProfile]] = try signingFilesLocator.locateProvisioningProfiles(at: entryPath)
            .map(provisioningProfileParser.parse)
            .reduce(into: [:], { dict, profile in
                var currentTargetDict = dict[profile.targetName] ?? [:]
                currentTargetDict[profile.configurationName] = profile
                dict[profile.targetName] = currentTargetDict
            })
        
        return (certificates: certificates, provisioningProfiles: provisioningProfiles)
    }
}
