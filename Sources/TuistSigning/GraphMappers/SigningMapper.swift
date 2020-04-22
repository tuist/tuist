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
    private let certificateController: CertificateControlling
    
    public convenience init() {
        self.init(signingFilesLocator: SigningFilesLocator(),
                  signingCipher: SigningCipher(),
                  provisioningProfileParser: ProvisioningProfileParser(),
                  signingInstaller: SigningInstaller(),
                  securityController: SecurityController(),
                  certificateController: CertificateController())
    }
    
    init(signingFilesLocator: SigningFilesLocating,
         signingCipher: SigningCiphering,
         provisioningProfileParser: ProvisioningProfileParsing,
         signingInstaller: SigningInstalling,
         securityController: SecurityControlling,
         certificateController: CertificateControlling) {
        self.signingFilesLocator = signingFilesLocator
        self.signingCipher = signingCipher
        self.provisioningProfileParser = provisioningProfileParser
        self.signingInstaller = signingInstaller
        self.securityController = securityController
        self.certificateController = certificateController
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
        let certificates = try zip(certificateFiles, privateKeyFiles)
            .map { publicKey, privateKey -> Certificate in
                let name = try certificateController.name(at: publicKey)
                return Certificate(publicKey: publicKey,
                                   privateKey: privateKey,
                                   name: name)
            }
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
        // Dictionary of [Profile.targetName: [Profile.configurationName: ProvisioningProfile]]
        let provisioningProfiles: [String: [String: ProvisioningProfile]] = try signingFilesLocator.locateProvisioningProfiles(at: entryPath)
            .map(provisioningProfileParser.parse)
            .reduce(into: [:], { dict, profile in
                var currentTargetDict = dict[profile.targetName] ?? [:]
                currentTargetDict[profile.configurationName] = profile
                dict[profile.targetName] = currentTargetDict
            })
        
        try graph.projects.forEach { project in
            project.targets = try project.targets.map {
                try map(target: $0,
                        project: project,
                        keychainPath: keychainPath,
                        certificates: certificates,
                        provisioningProfiles: provisioningProfiles)
            }
        }
        return (graph, [])
    }
    
    private func map(target: Target,
                     project: Project,
                     keychainPath: AbsolutePath,
                     certificates: [String: Certificate],
                     provisioningProfiles: [String: [String: ProvisioningProfile]]) throws -> Target {
        var target = target
        let configurationsDict = target.settings?.configurations ?? project.settings.configurations
        let configurations: [BuildConfiguration: Configuration?] =
            configurationsDict
                .reduce(into: [:]) { dict, configurationPair in
                    guard
                        let provisioningProfile = provisioningProfiles[target.name]?[configurationPair.key.name],
                        let certificate = certificates[configurationPair.key.name.lowercased()]
                    else {
                        dict[configurationPair.key] = configurationPair.value
                        return
                    }
                    var configuration = configurationPair.value ?? Configuration()
                    configuration.settings["CODE_SIGN_STYLE"] = "Manual"
                    configuration.settings["CODE_SIGN_IDENTITY"] = SettingValue(stringLiteral: certificate.name)
                    configuration.settings["OTHER_CODE_SIGN_FLAGS"] = SettingValue(stringLiteral: "--keychain \(keychainPath.pathString)")
                    configuration.settings["DEVELOPMENT_TEAM"] = SettingValue(stringLiteral: provisioningProfile.teamID)
                    configuration.settings["PROVISIONING_PROFILE_SPECIFIER"] = SettingValue(stringLiteral: provisioningProfile.uuid)
                    dict[configurationPair.key] = configuration
        }
        
        target.settings = Settings(base: target.settings?.base ?? [:],
                                   configurations: configurations,
                                   defaultSettings: target.settings?.defaultSettings ?? .recommended)
        
        try Array(configurationsDict.keys).compactMap {
            provisioningProfiles[target.name]?[$0.name]
        }
        // TODO: Change to side effects
        .forEach(signingInstaller.installProvisioningProfile)
        return target
    }
}
