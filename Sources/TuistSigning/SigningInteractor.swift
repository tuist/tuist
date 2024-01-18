import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

/// Interacts with signing
public protocol SigningInteracting {
    /// Install signing for a given graph
    func install(graphTraverser: GraphTraversing) throws -> [LintingIssue]
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

    public func install(graphTraverser: GraphTraversing) throws -> [LintingIssue] {
        let entryPath = graphTraverser.path
        guard let signingDirectory = try signingFilesLocator.locateSigningDirectory(from: entryPath),
              let derivedDirectory = rootDirectoryLocator.locate(from: entryPath)?
              .appending(component: Constants.DerivedDirectory.name)
        else { return [] }

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

        return try graphTraverser.allTargets().sorted().flatMap { target in
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
    ) throws -> [LintingIssue] {
        let targetConfigurations = target.target.settings?.configurations ?? [:]
        /// Filtering certificate-provisioning profile pairs, so they are installed only when necessary (they correspond to some
        /// configuration and target in the project)
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

        for signingPair in signingPairs.map(\.certificate) {
            try signingInstaller.installCertificate(signingPair, keychainPath: keychainPath)
        }

        let provisioningProfileInstallLintIssues = try signingPairs.map(\.provisioningProfile)
            .flatMap(signingInstaller.installProvisioningProfile)
        try provisioningProfileInstallLintIssues.printAndThrowErrorsIfNeeded()

        let provisioningProfileLintIssues = signingPairs.map(\.provisioningProfile).flatMap {
            signingLinter.lint(provisioningProfile: $0, target: target.target)
        }
        try provisioningProfileLintIssues.printAndThrowErrorsIfNeeded()

        let signingPairLintIssues = signingPairs.flatMap(signingLinter.lint)
        try signingPairLintIssues.printAndThrowErrorsIfNeeded()

        let certificateLintIssues = signingPairs.map(\.certificate).flatMap(signingLinter.lint)
        try certificateLintIssues.printAndThrowErrorsIfNeeded()

        return [
            provisioningProfileInstallLintIssues,
            provisioningProfileLintIssues,
            signingPairLintIssues,
            certificateLintIssues,
        ].flatMap { $0 }
    }
}
