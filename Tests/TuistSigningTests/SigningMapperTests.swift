import XCTest
import TSCBasic
import TuistCore
import TuistSupport
@testable import TuistSigningTesting
@testable import TuistCoreTesting
@testable import TuistSupportTesting
@testable import TuistSigning

final class SigningMapperTests: TuistUnitTestCase {
    var subject: SigningMapper!
    var signingFilesLocator: MockSigningFilesLocator!
    var signingMatcher: MockSigningMatcher!
    var rootDirectoryLocator: MockRootDirectoryLocator!
    var signingCipher: MockSigningCipher!
    
    override func setUp() {
        super.setUp()
        signingFilesLocator = MockSigningFilesLocator()
        signingMatcher = MockSigningMatcher()
        rootDirectoryLocator = MockRootDirectoryLocator()
        signingCipher = MockSigningCipher()
        
        subject = SigningMapper(
            signingFilesLocator: signingFilesLocator,
            signingMatcher: signingMatcher,
            rootDirectoryLocator: rootDirectoryLocator,
            signingCipher: signingCipher
        )
    }
    
    override func tearDown() {
        super.tearDown()
        signingFilesLocator = nil
        signingMatcher = nil
        rootDirectoryLocator = nil
        signingCipher = nil
        subject = nil
    }
    
    func test_signing_mapping() throws {
        // Given
        let signingDirectory = try temporaryPath()
        signingFilesLocator.locateSigningDirectoryStub = { _ in
            signingDirectory
        }
        let rootDirectory = try temporaryPath()
        let derivedDirectory = rootDirectory.appending(component: Constants.derivedFolderName)
        let keychainPath = derivedDirectory.appending(component: Constants.signingKeychain)
        rootDirectoryLocator.locateStub = rootDirectory
        let targetName = "target"
        let configuration = "configuration"
        let certificate = Certificate.test(name: "certA")
        let provisioningProfile = ProvisioningProfile.test(
            name: "profileA",
            teamId: "TeamID",
            appId: "TeamID.BundleID"
        )
        signingMatcher.matchStub = { _ in
            (certificates: [
                configuration: certificate,
            ],
             provisioningProfiles: [
                targetName: [
                    configuration: provisioningProfile,
                ]
            ])
        }
        
        let target = Target.test(
            name: targetName,
            bundleId: "BundleID",
            settings: Settings(
                configurations: [
                    BuildConfiguration(
                        name: configuration,
                        variant: .debug
                    ): Configuration.test(settings: [
                        "SOME_SETTING": "Value"
                    ])
            ]
        ))
        
        let expectedConfigurations: [BuildConfiguration: Configuration] = [
            BuildConfiguration(
                name: configuration,
                variant: .debug
            ): Configuration.test(settings: [
                "SOME_SETTING": "Value",
                "CODE_SIGN_STYLE": "Manual",
                "CODE_SIGN_IDENTITY": SettingValue(stringLiteral: certificate.name),
                "OTHER_CODE_SIGN_FLAGS": SettingValue(stringLiteral: "--keychain \(keychainPath.pathString)"),
                "DEVELOPMENT_TEAM": SettingValue(stringLiteral: provisioningProfile.teamId),
                "PROVISIONING_PROFILE_SPECIFIER": SettingValue(stringLiteral: provisioningProfile.uuid)
            ])
        ]
        
        let project = Project.test(targets: [target])
        let graph = Graph.test(projects: [project])
        
        // When
        let (mappedGraph, sideEffects) = try subject.map(graph: graph)
        
        // Then
        XCTAssertEmpty(sideEffects)
        let configurations = mappedGraph.projects
            .flatMap(\.targets)
            .map(\.settings)
            .map { $0?.configurations }
        
        XCTAssertEqual(configurations.first, expectedConfigurations)
    }
    
    func test_signing_mapping_when_mismatched_app_id() throws {
        // Given
        let signingDirectory = try temporaryPath()
        signingFilesLocator.locateSigningDirectoryStub = { _ in
            signingDirectory
        }
        let rootDirectory = try temporaryPath()
        rootDirectoryLocator.locateStub = rootDirectory
        let targetName = "target"
        let configuration = "configuration"
        let certificate = Certificate.test(name: "certA")
        let provisioningProfile = ProvisioningProfile.test(
            name: "profileA",
            teamId: "TeamID",
            appId: "TeamID.MismatchedBundleID"
        )
        signingMatcher.matchStub = { _ in
            (certificates: [
                configuration: certificate,
            ],
             provisioningProfiles: [
                targetName: [
                    configuration: provisioningProfile,
                ]
            ])
        }
        
        let target = Target.test(
            name: targetName,
            bundleId: "BundleID",
            settings: Settings(
                configurations: [
                    BuildConfiguration(
                        name: configuration,
                        variant: .debug
                    ): Configuration.test()
            ]
        ))
        
        let project = Project.test(targets: [target])
        let graph = Graph.test(projects: [project])
        
        // When
        XCTAssertThrowsSpecific(
            try subject.map(graph: graph),
            SigningMapperError.appIdMismatch(
                "TeamID.MismatchedBundleID",
                "TeamID",
                "BundleID"
            )
        )
    }
}
