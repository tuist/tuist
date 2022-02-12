import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

/// Interacts with signing
public protocol SigningInteracting {
    /// Install signing for a given graph
    func install(graphTraverser: GraphTraversing) throws
}

public final class SigningInteractor: SigningInteracting {
    private let signingFilesLocator: SigningFilesLocating
    private let rootDirectoryLocator: RootDirectoryLocating
    private let signingMatcher: SigningMatching
    private let signingInstaller: SigningInstalling
    private let signingLinter: SigningLinting
    private let securityController: SecurityControlling
    private let signingCipher: SigningCiphering

    public convenience init() {
        self.init(
            signingFilesLocator: SigningFilesLocator(),
            rootDirectoryLocator: RootDirectoryLocator(),
            signingMatcher: SigningMatcher(),
            signingInstaller: SigningInstaller(),
            signingLinter: SigningLinter(),
            securityController: SecurityController(),
            signingCipher: SigningCipher()
        )
    }

    init(
        signingFilesLocator: SigningFilesLocating,
        rootDirectoryLocator: RootDirectoryLocating,
        signingMatcher: SigningMatching,
        signingInstaller: SigningInstalling,
        signingLinter: SigningLinting,
        securityController: SecurityControlling,
        signingCipher: SigningCiphering
    ) {
        self.signingFilesLocator = signingFilesLocator
        self.rootDirectoryLocator = rootDirectoryLocator
        self.signingMatcher = signingMatcher
        self.signingInstaller = signingInstaller
        self.signingLinter = signingLinter
        self.securityController = securityController
        self.signingCipher = signingCipher
    }

    public func install(graphTraverser: GraphTraversing) throws {
        let entryPath = graphTraverser.path
        guard let signingDirectory = try signingFilesLocator.locateSigningDirectory(from: entryPath),
              let derivedDirectory = rootDirectoryLocator.locate(from: entryPath)?
              .appending(component: Constants.DerivedDirectory.name)
        else { return }

        let keychainPath = derivedDirectory.appending(component: Constants.DerivedDirectory.signingKeychain)

        let masterKey = try signingCipher.readMasterKey(at: signingDirectory)
        try FileHandler.shared.createFolder(derivedDirectory)
        if !FileHandler.shared.exists(keychainPath) {
            try securityController.createKeychain(at: keychainPath, password: masterKey)
        }
        try securityController.unlockKeychain(at: keychainPath, password: masterKey)
        defer { try? securityController.lockKeychain(at: keychainPath, password: masterKey) }

        try signingCipher.decryptSigning(at: entryPath, keepFiles: true)
        defer { try? signingCipher.encryptSigning(at: entryPath, keepFiles: false) }

        let (certificates, provisioningProfiles) = try signingMatcher.match(from: graphTraverser.path)

        try graphTraverser.allTargets().sorted().forEach { target in
            try install(
                target: target,
                keychainPath: keychainPath,
                certificates: certificates,
                provisioningProfiles: provisioningProfiles
            )
        }
    }

    // MARK: - Helpers

    private func install(
        target: GraphTarget,
        keychainPath: AbsolutePath,
        certificates: [Fingerprint: Certificate],
        provisioningProfiles: [TargetName: [ConfigurationName: ProvisioningProfile]]
    ) throws {
        let targetConfigurations = target.target.settings?.configurations ?? [:]
        /// Filtering certificate-provisioning profile pairs, so they are installed only when necessary (they correspond to some configuration and target in the project)
        let signingPairs = Set(
            targetConfigurations
                .merging(
                    target.project.settings.configurations,
                    uniquingKeysWith: { config, _ in config }
                )
                .keys
        )
        .compactMap { configuration -> (certificate: Certificate, provisioningProfile: ProvisioningProfile)? in
            guard let provisioningProfile = provisioningProfiles[target.target.name]?[configuration.name],
                  let certificate = certificates.first(for: provisioningProfile)
            else {
                return nil
            }
            return (certificate: certificate, provisioningProfile: provisioningProfile)
        }

        try signingPairs.map(\.certificate).forEach {
            try signingInstaller.installCertificate($0, keychainPath: keychainPath)
        }
        try signingPairs.map(\.provisioningProfile)
            .flatMap(signingInstaller.installProvisioningProfile)
            .printAndThrowIfNeeded()
        try signingPairs.map(\.provisioningProfile).flatMap {
            signingLinter.lint(provisioningProfile: $0, target: target.target)
        }.printAndThrowIfNeeded()

        try signingPairs.flatMap(signingLinter.lint).printAndThrowIfNeeded()
        try signingPairs.map(\.certificate).flatMap(signingLinter.lint).printAndThrowIfNeeded()
    }
}
