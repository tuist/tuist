import FileSystem
import Foundation
import Mockable
import Testing
import TuistLoader
import TuistServer
import TuistSupport
import TuistSupportTesting

@testable import TuistKit

struct RegistrySetupCommandServiceTests {
    private let serverURLService = MockServerURLServicing()
    private let configLoader = MockConfigLoading()
    private let fileSystem = FileSystem()
    private let fullHandleService = MockFullHandleServicing()
    private let manifestFilesLocator = MockManifestFilesLocating()
    private let swiftPackageManagerController = MockSwiftPackageManagerControlling()
    private let createAccountTokenService = MockCreateAccountTokenServicing()
    private let defaultsController = MockDefaultsControlling()
    private let subject: RegistrySetupCommandService

    init() {
        subject = RegistrySetupCommandService(
            serverURLService: serverURLService,
            configLoader: configLoader,
            fileSystem: fileSystem,
            fullHandleService: fullHandleService,
            manifestFilesLocator: manifestFilesLocator,
            swiftPackageManagerController: swiftPackageManagerController,
            createAccountTokenService: createAccountTokenService,
            defaultsController: defaultsController
        )

        given(swiftPackageManagerController)
            .packageRegistryLogin(token: .any, registryURL: .any)
            .willReturn()
        given(createAccountTokenService)
            .createAccountToken(accountHandle: .any, scopes: .any, serverURL: .any)
            .willReturn("token")
        given(defaultsController)
            .setPackageDendencySCMToRegistryTransformation(.any)
            .willReturn()
    }

    @Test func test_setup_when_a_package_manifest_is_found() async throws {
        try await withTestingDependencies {
            try await fileSystem.runInTemporaryDirectory(prefix: "setup") { temporaryPath in
                // Given
                given(configLoader)
                    .loadConfig(path: .any)
                    .willReturn(.test(fullHandle: "tuist/tuist"))
                given(fullHandleService)
                    .parse(.any)
                    .willReturn((accountHandle: "tuist", projectHandle: "tuist"))
                given(serverURLService)
                    .url(configServerURL: .any)
                    .willReturn(.test())
                given(manifestFilesLocator)
                    .locatePackageManifest(at: .any)
                    .willProduce { $0.appending(component: "Package.swift") }

                // When
                try await subject.run(path: temporaryPath.pathString)

                // Then
                let configurationPath = temporaryPath.appending(
                    components: ".swiftpm", "configuration", "registries.json"
                )
                let exists = try await fileSystem.exists(configurationPath)
                #expect(exists)
                let fileContents = try await fileSystem.readTextFile(at: configurationPath)
                #expect(
                    fileContents == """
                    {
                      "security": {
                        "default": {
                          "signing": {
                            "onUnsigned": "silentAllow"
                          }
                        }
                      },
                      "authentication": {
                        "test.tuist.io": {
                          "loginAPIPath": "/api/accounts/tuist/registry/swift/login",
                          "type": "token"
                        }
                      },
                      "registries": {
                        "[default]": {
                          "supportsAvailability": false,
                          "url": "\(URL.test())/api/accounts/tuist/registry/swift"
                        }
                      },
                      "version": 1
                    }

                    """
                )
                verify(createAccountTokenService)
                    .createAccountToken(accountHandle: .any, scopes: .any, serverURL: .any)
                    .called(1)
                verify(swiftPackageManagerController)
                    .packageRegistryLogin(token: .any, registryURL: .any)
                    .called(1)
                verify(defaultsController)
                    .setPackageDendencySCMToRegistryTransformation(.any)
                    .called(0)
            }
        }
    }

    @Test func test_setup_when_an_xcode_project_is_found() async throws {
        try await withTestingDependencies {
            try await fileSystem.runInTemporaryDirectory(prefix: "setup") { temporaryPath in
                // Given
                given(configLoader)
                    .loadConfig(path: .any)
                    .willReturn(.test(fullHandle: "tuist/tuist"))
                given(fullHandleService)
                    .parse(.any)
                    .willReturn((accountHandle: "tuist", projectHandle: "tuist"))
                given(serverURLService)
                    .url(configServerURL: .any)
                    .willReturn(.test())
                given(manifestFilesLocator)
                    .locatePackageManifest(at: .any)
                    .willReturn(nil)
                try await fileSystem.makeDirectory(
                    at: temporaryPath.appending(component: "Tuist.xcodeproj")
                )

                // When
                try await subject.run(path: temporaryPath.pathString)

                // Then
                let exists = try await fileSystem.exists(
                    temporaryPath.appending(
                        components: "Tuist.xcodeproj",
                        "project.xcworkspace",
                        "xcshareddata",
                        "swiftpm",
                        "configuration",
                        "registries.json"
                    )
                )
                #expect(exists)
                verify(defaultsController)
                    .setPackageDendencySCMToRegistryTransformation(.any)
                    .called(1)
                #expect(ui().contains("Logged in to the tuist registry") == true)
                #expect(
                    ui()
                        .contains(
                            "Generated the tuist registry configuration file at Tuist.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/configuration/registries.json"
                        ) == true
                )
            }
        }
    }

    @Test func test_setup_when_an_xcode_workspace_is_found() async throws {
        try await withTestingDependencies {
            try await fileSystem.runInTemporaryDirectory(prefix: "setup") { temporaryPath in
                // Given
                given(configLoader)
                    .loadConfig(path: .any)
                    .willReturn(.test(fullHandle: "tuist/tuist"))
                given(fullHandleService)
                    .parse(.any)
                    .willReturn((accountHandle: "tuist", projectHandle: "tuist"))
                given(serverURLService)
                    .url(configServerURL: .any)
                    .willReturn(.test())
                given(manifestFilesLocator)
                    .locatePackageManifest(at: .any)
                    .willReturn(nil)
                try await fileSystem.makeDirectory(
                    at: temporaryPath.appending(component: "Tuist.xcworkspace")
                )

                // When
                try await subject.run(path: temporaryPath.pathString)

                // Then
                let exists = try await fileSystem.exists(
                    temporaryPath.appending(
                        components: "Tuist.xcworkspace",
                        "xcshareddata",
                        "swiftpm",
                        "configuration",
                        "registries.json"
                    )
                )
                #expect(exists)
                verify(defaultsController)
                    .setPackageDendencySCMToRegistryTransformation(.any)
                    .called(1)
            }
        }
    }
}
