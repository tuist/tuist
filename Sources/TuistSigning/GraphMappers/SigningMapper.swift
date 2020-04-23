import Foundation
import TSCBasic
import TuistCore
import TuistSupport

public class SigningMapper: GraphMapping {
    private let signingFilesLocator: SigningFilesLocating
    private let rootDirectoryLocator: RootDirectoryLocating
    private let signingMatcher: SigningMatching
    
    public convenience init() {
        self.init(signingFilesLocator: SigningFilesLocator(),
                  signingMatcher: SigningMatcher(),
                  rootDirectoryLocator: RootDirectoryLocator())
    }
    
    init(signingFilesLocator: SigningFilesLocating,
         signingMatcher: SigningMatching,
         rootDirectoryLocator: RootDirectoryLocating) {
        self.signingFilesLocator = signingFilesLocator
        self.signingMatcher = signingMatcher
        self.rootDirectoryLocator = rootDirectoryLocator
    }
    
    // MARK: - GraphMapping
    public func map(graph: Graph) throws -> (Graph, [SideEffectDescriptor]) {
        let entryPath = graph.entryPath
        guard
            try signingFilesLocator.locateSigningDirectory(at: entryPath) != nil,
            let derivedDirectory = rootDirectoryLocator.locate(from: entryPath)?.appending(component: Constants.derivedFolderName)
        else { return (graph, []) }
        
        let keychainPath = derivedDirectory.appending(component: Constants.signingKeychain)
        
        let (certificates, provisioningProfiles) = try signingMatcher.match(graph: graph)
        
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
        let targetConfigurations = target.settings?.configurations ?? [:]
        let configurations: [BuildConfiguration: Configuration?] = targetConfigurations
            .merging(project.settings.configurations,
                     uniquingKeysWith: { config, _ in config })
            .reduce(into: [:]) { dict, configurationPair in
                guard
                    let provisioningProfile = provisioningProfiles[target.name]?[configurationPair.key.name],
                    let certificate = certificates[configurationPair.key.name.lowercased()]
                    else {
                        dict[configurationPair.key] = configurationPair.value
                        return
                    }
                guard provisioningProfile.appID == provisioningProfile.teamID + "." + target.bundleId else { fatalError() }
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
        return target
    }
}
