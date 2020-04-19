import Foundation
import TSCBasic
import TuistCore
import TuistSupport

public class SigningMapper: GraphMapping {
    private let signingFilesLocator: SigningFilesLocating
    private let signingCipher: SigningCiphering
    private let provisioningProfileParser: ProvisioningProfileParsing
    private let signingInstaller: SigningInstalling
    private let securityController: SecurityControlling
    
    public convenience init() {
        self.init(signingFilesLocator: SigningFilesLocator(),
                  signingCipher: SigningCipher(),
                  provisioningProfileParser: ProvisioningProfileParser(),
                  signingInstaller: SigningInstaller(),
                  securityController: SecurityController())
    }
    
    init(signingFilesLocator: SigningFilesLocating,
         signingCipher: SigningCiphering,
         provisioningProfileParser: ProvisioningProfileParsing,
         signingInstaller: SigningInstalling,
         securityController: SecurityControlling) {
        self.signingFilesLocator = signingFilesLocator
        self.signingCipher = signingCipher
        self.provisioningProfileParser = provisioningProfileParser
        self.signingInstaller = signingInstaller
        self.securityController = securityController
    }
    
    // MARK: - GraphMapping
    public func map(graph: Graph) throws -> (Graph, [SideEffectDescriptor]) {
        let entryPath = graph.entryPath
        guard let signingDirectory = try signingFilesLocator.locateSigningDirectory(at: entryPath) else { return (graph, []) }
        
        try signingCipher.decryptSigning(at: entryPath)
        defer { try? signingCipher.encryptSigning(at: entryPath) }
        
        let keychainPath = signingDirectory.appending(component: Constants.signingKeychain)
        let masterKey = try signingCipher.readMasterKey(at: signingDirectory)
        try securityController.createKeychain(at: keychainPath, password: masterKey)
        try securityController.unlockKeychain(at: keychainPath, password: masterKey)
        defer { try? securityController.lockKeychain(at: keychainPath, password: masterKey) }
        
        let certificateFiles = try signingFilesLocator.locateUnencryptedCertificates(at: entryPath)
            .sorted()
        let privateKeyFiles = try signingFilesLocator.locateUnencryptedPrivateKeys(at: entryPath)
            .sorted()
        let certificates = zip(certificateFiles, privateKeyFiles)
            .map(Certificate.init)
            .reduce(into: [:]) { dict, certificate in
                dict[certificate.publicKey.basenameWithoutExt] = certificate
            }
            
        
        let configurations = (graph.projects
            .map { $0.settings.configurations }
            + graph.projects.flatMap { $0.targets.compactMap { $0.settings?.configurations } })
            .flatMap { Set($0.keys).map { $0.name.lowercased() } }
        
        try configurations
            .compactMap { certificates[$0] /* TODO: Add warning if not available */ }
            .forEach { try securityController.importCertificate($0, keychainPath: keychainPath) }
        let provisioningProfiles: [String: [String: ProvisioningProfile]] = try signingFilesLocator.locateProvisioningProfiles(at: entryPath)
            .map(provisioningProfileParser.parse)
            .reduce(into: [:], { dict, profile in
                dict[profile.targetName]?[profile.configurationName] = profile
            })
        
        let results = try graph.projects.flatMap { project in
            try project.targets.map {
                try map(target: $0,
                        project: project,
                        provisioningProfiles: provisioningProfiles)
            }
        }
        let sideEffects = results.map { $0.1 }.flatMap { $0 }
        return (graph, sideEffects)
    }
    
    private func map(target: Target,
                     project: Project,
                     provisioningProfiles: [String: [String: ProvisioningProfile]]) throws -> (Target, [SideEffectDescriptor]) {
        let configurationsDict = target.settings?.configurations ?? project.settings.configurations
        let configurations = Array(configurationsDict.keys)
        
        try configurations.compactMap {
            provisioningProfiles[target.name]?[$0.name]
        }
        // TODO: Change to side effects
        .map(signingInstaller.installProvisioningProfile)
        return (target, [])
    }
}
