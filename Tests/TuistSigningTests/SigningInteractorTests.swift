import TSCBasic
import TuistCore
import TuistSupport
import XCTest
@testable import TuistCoreTesting
@testable import TuistSigning
@testable import TuistSigningTesting
@testable import TuistSupportTesting

final class SigningInteractorTests: TuistUnitTestCase {
    var subject: SigningInteractor!
    var signingFilesLocator: MockSigningFilesLocator!
    var rootDirectoryLocator: MockRootDirectoryLocator!
    var signingMatcher: MockSigningMatcher!
    var signingInstaller: MockSigningInstaller!
    var signingLinter: MockSigningLinter!
    var securityController: MockSecurityController!
    var signingCipher: MockSigningCipher!

    override func setUp() {
        super.setUp()
        signingFilesLocator = MockSigningFilesLocator()
        rootDirectoryLocator = MockRootDirectoryLocator()
        signingMatcher = MockSigningMatcher()
        signingInstaller = MockSigningInstaller()
        signingLinter = MockSigningLinter()
        securityController = MockSecurityController()
        signingCipher = MockSigningCipher()

        subject = SigningInteractor(
            signingFilesLocator: signingFilesLocator,
            rootDirectoryLocator: rootDirectoryLocator,
            signingMatcher: signingMatcher,
            signingInstaller: signingInstaller,
            signingLinter: signingLinter,
            securityController: securityController,
            signingCipher: signingCipher
        )
    }

    override func tearDown() {
        super.tearDown()
        signingFilesLocator = nil
        rootDirectoryLocator = nil
        signingMatcher = nil
        signingInstaller = nil
        signingLinter = nil
        securityController = nil
        signingCipher = nil
        subject = nil
    }

    func test_install_creates_keychain() throws {
        // Given
        let graph = Graph.test()
        let signingDirectory = try temporaryPath()
        signingFilesLocator.locateSigningDirectoryStub = { _ in
            signingDirectory
        }
        let masterKey = "master-key"
        signingCipher.readMasterKeyStub = { _ in
            masterKey
        }

        let rootDirectory = try temporaryPath()
        rootDirectoryLocator.locateStub = rootDirectory
        let keychainDirectory = rootDirectory
            .appending(components: Constants.DerivedDirectory.name, Constants.DerivedDirectory.signingKeychain)

        var receivedKeychainDirectory: AbsolutePath?
        var receivedMasterKey: String?
        securityController.createKeychainStub = {
            receivedKeychainDirectory = $0
            receivedMasterKey = $1
        }

        // When
        try subject.install(graph: graph)

        // Then
        XCTAssertEqual(masterKey, receivedMasterKey)
        XCTAssertEqual(keychainDirectory, receivedKeychainDirectory)
    }

    func test_install_unlocks_keychain() throws {
        // Given
        let graph = Graph.test()
        let signingDirectory = try temporaryPath()
        signingFilesLocator.locateSigningDirectoryStub = { _ in
            signingDirectory
        }
        let masterKey = "master-key"
        signingCipher.readMasterKeyStub = { _ in
            masterKey
        }

        let rootDirectory = try temporaryPath()
        rootDirectoryLocator.locateStub = rootDirectory
        let keychainDirectory = rootDirectory
            .appending(components: Constants.DerivedDirectory.name, Constants.DerivedDirectory.signingKeychain)

        var receivedKeychainDirectory: AbsolutePath?
        var receivedMasterKey: String?
        securityController.unlockKeychainStub = {
            receivedKeychainDirectory = $0
            receivedMasterKey = $1
        }

        // When
        try subject.install(graph: graph)

        // Then
        XCTAssertEqual(masterKey, receivedMasterKey)
        XCTAssertEqual(keychainDirectory, receivedKeychainDirectory)
    }

    func test_install_locks_keychain() throws {
        // Given
        let graph = Graph.test()
        signingFilesLocator.locateSigningDirectoryStub = { _ in
            try self.temporaryPath()
        }
        let masterKey = "master-key"
        signingCipher.readMasterKeyStub = { _ in
            masterKey
        }

        let rootDirectory = try temporaryPath()
        rootDirectoryLocator.locateStub = rootDirectory
        let keychainDirectory = rootDirectory
            .appending(components: Constants.DerivedDirectory.name, Constants.DerivedDirectory.signingKeychain)

        var receivedKeychainDirectory: AbsolutePath?
        var receivedMasterKey: String?
        securityController.lockKeychainStub = {
            receivedKeychainDirectory = $0
            receivedMasterKey = $1
        }

        // When
        try subject.install(graph: graph)

        // Then
        XCTAssertEqual(masterKey, receivedMasterKey)
        XCTAssertEqual(keychainDirectory, receivedKeychainDirectory)
    }

    func test_install_decrypts_signing() throws {
        // Given
        let entryPath = try temporaryPath()
        let graph = Graph.test(entryPath: entryPath)
        signingFilesLocator.locateSigningDirectoryStub = { _ in
            try self.temporaryPath()
        }
        signingCipher.readMasterKeyStub = { _ in
            "master-key"
        }

        rootDirectoryLocator.locateStub = try temporaryPath()

        var signingPath: AbsolutePath?
        var keepFiles: Bool?
        signingCipher.decryptSigningStub = {
            signingPath = $0
            keepFiles = $1
        }

        // When
        try subject.install(graph: graph)

        // Then
        XCTAssertEqual(signingPath, entryPath)
        XCTAssertTrue(keepFiles ?? false)
    }

    func test_install_encrypts_signing() throws {
        // Given
        let entryPath = try temporaryPath()
        let graph = Graph.test(entryPath: entryPath)
        signingFilesLocator.locateSigningDirectoryStub = { _ in
            try self.temporaryPath()
        }
        signingCipher.readMasterKeyStub = { _ in
            "master-key"
        }

        rootDirectoryLocator.locateStub = try temporaryPath()

        var signingPath: AbsolutePath?
        var keepFiles: Bool?
        signingCipher.encryptSigningStub = {
            signingPath = $0
            keepFiles = $1
        }

        // When
        try subject.install(graph: graph)

        // Then
        XCTAssertEqual(signingPath, entryPath)
        XCTAssertFalse(keepFiles ?? true)
    }

    func test_installs_signing() throws {
        // Given
        try prepareSigning()
        let targetName = "target"
        let configuration = "configuration"
        let expectedCertificate = Certificate.test(name: "certA")
        let expectedProvisioningProfile = ProvisioningProfile.test(name: "profileA")
        signingMatcher.matchStub = { _ in
            (certificates: [
                targetName: [
                    configuration: expectedCertificate,
                    // Used to ensure only certificates that have configuration are installed
                    "other-config": Certificate.test(name: "certB"),
                ],
            ],
            provisioningProfiles: [
                targetName: [
                    configuration: expectedProvisioningProfile,
                    "some-other-config": ProvisioningProfile.test(),
                ],
            ])
        }

        let target = Target.test(
            name: targetName,
            settings: Settings(
                configurations: [
                    BuildConfiguration(
                        name: configuration,
                        variant: .debug
                    ): Configuration.test(),
                ]
            )
        )
        let project = Project.test(targets: [target])
        let graph = Graph.test(projects: [project])

        var installedCertificates: [Certificate] = []
        signingInstaller.installCertificateStub = { certificate, _ in
            installedCertificates.append(certificate)
        }
        var installedProvisioningProfiles: [ProvisioningProfile] = []
        signingInstaller.installProvisioningProfileStub = { profile in
            installedProvisioningProfiles.append(profile)
        }

        // When
        try subject.install(graph: graph)

        // Then
        XCTAssertEqual([expectedCertificate], installedCertificates)
        XCTAssertEqual([expectedProvisioningProfile], installedProvisioningProfiles)
    }

    // MARK: - Helpers

    private func prepareSigning() throws {
        signingFilesLocator.locateSigningDirectoryStub = { _ in
            try self.temporaryPath()
        }
        signingCipher.readMasterKeyStub = { _ in
            "master-key"
        }

        rootDirectoryLocator.locateStub = try temporaryPath()
    }
}
