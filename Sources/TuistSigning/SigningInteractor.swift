import Foundation
import TSCBasic
import TuistCore
import TuistSupport

public protocol SigningInteracting {
    func install(graph: Graph) throws
}

public final class SigningInteractor: SigningInteracting {
    private let signingFilesLocator: SigningFilesLocating
    private let signingMatcher: SigningMatching
    private let signingInstaller: SigningInstalling
    private let signingLinter: SigningLinting
    
    public convenience init() {
        self.init(signingFilesLocator: SigningFilesLocator(),
                  signingMatcher: SigningMatcher(),
                  signingInstaller: SigningInstaller(),
                  signingLinter: SigningLinter())
    }
    
    init(signingFilesLocator: SigningFilesLocating,
         signingMatcher: SigningMatching,
         signingInstaller: SigningInstalling,
         signingLinter: SigningLinting) {
        self.signingFilesLocator = signingFilesLocator
        self.signingMatcher = signingMatcher
        self.signingInstaller = signingInstaller
        self.signingLinter = signingLinter
    }
    
    public func install(graph: Graph) throws {
        let entryPath = graph.entryPath
        guard let signingDirectory = try signingFilesLocator.locateSigningDirectory(at: entryPath) else { return }
        
        let keychainPath = signingDirectory.appending(component: Constants.signingKeychain)
        
        let (certificates, provisioningProfiles) = try signingMatcher.match(graph: graph)
        
        try graph.projects.forEach { project in
            try project.targets.forEach {
                try install(target: $0,
                            project: project,
                            keychainPath: keychainPath,
                            certificates: certificates,
                            provisioningProfiles: provisioningProfiles)
            }
        }
    }
    
    private func install(target: Target,
                         project: Project,
                         keychainPath: AbsolutePath,
                         certificates: [String: Certificate],
                         provisioningProfiles: [String: [String: ProvisioningProfile]]) throws {
        let targetConfigurations = target.settings?.configurations ?? [:]
        let signingPairs = Set(targetConfigurations
            .merging(project.settings.configurations,
                     uniquingKeysWith: { config, _ in config })
            .keys)
            .compactMap { configuration -> (certificate: Certificate, provisioningProfile: ProvisioningProfile)? in
                guard
                    let provisioningProfile = provisioningProfiles[target.name]?[configuration.name],
                    let certificate = certificates[configuration.name.lowercased()]
                    else {
                        return nil
                }
                return (certificate: certificate, provisioningProfile: provisioningProfile)
        }
        
        try signingPairs.map(\.certificate).forEach {
            try signingInstaller.installCertificate($0, keychainPath: keychainPath)
        }
        try signingPairs.map(\.provisioningProfile).forEach(signingInstaller.installProvisioningProfile)
        
        try signingPairs.flatMap(signingLinter.lint).printAndThrowIfNeeded()
    }
}
