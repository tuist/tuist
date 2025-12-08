import FileSystem
import Foundation
import Mockable
import Testing
import TuistLoader
import TuistServer
import TuistSupport
import TuistTesting

@testable import TuistKit

struct RegistrySetupCommandServiceTests {
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let configLoader = MockConfigLoading()
    private let fileSystem = FileSystem()
    private let manifestFilesLocator = MockManifestFilesLocating()
    private let swiftPackageManagerController = MockSwiftPackageManagerControlling()
    private let createAccountTokenService = MockCreateAccountTokenServicing()
    private let defaultsController = MockDefaultsControlling()
    private let subject: RegistrySetupCommandService

    init() {
        subject = RegistrySetupCommandService(
            serverEnvironmentService: serverEnvironmentService,
            configLoader: configLoader,
            fileSystem: fileSystem,
            manifestFilesLocator: manifestFilesLocator,
            swiftPackageManagerController: swiftPackageManagerController,
            createAccountTokenService: createAccountTokenService,
            defaultsController: defaultsController
        )

        given(createAccountTokenService)
            .createAccountToken(
                accountHandle: .any,
                scopes: .any,
                name: .any,
                expiresAt: .any,
                projectHandles: .any,
                serverURL: .any
            )
            .willReturn(.init(id: "token-id", token: "token"))
        given(defaultsController)
            .setPackageDendencySCMToRegistryTransformation(.any)
            .willReturn()
    }

    @Test func setup_when_a_package_manifest_is_found() async throws {
        try await withMockedDependencies {
            try await fileSystem.runInTemporaryDirectory(prefix: "setup") { temporaryPath in
                // Given
                given(configLoader)
                    .loadConfig(path: .any)
                    .willReturn(.test())
                given(serverEnvironmentService)
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
                          "loginAPIPath": "/api/registry/swift/login",
                          "type": "token"
                        }
                      },
                      "registries": {
                        "[default]": {
                          "supportsAvailability": false,
                          "url": "\(URL.test())/api/registry/swift"
                        }
                      },
                      "version": 1
                    }

                    """
                )
                verify(defaultsController)
                    .setPackageDendencySCMToRegistryTransformation(.any)
                    .called(0)
            }
        }
    }

    @Test func setup_when_an_xcode_project_is_found() async throws {
        try await withMockedDependencies {
            try await fileSystem.runInTemporaryDirectory(prefix: "setup") { temporaryPath in
                // Given
                given(configLoader)
                    .loadConfig(path: .any)
                    .willReturn(.test())
                given(serverEnvironmentService)
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
                #expect(
                    ui()
                        .contains(
                            "Generated the registry configuration file at Tuist.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/configuration/registries.json"
                        ) == true
                )
            }
        }
    }

    @Test func setup_when_an_xcode_workspace_is_found() async throws {
        try await withMockedDependencies {
            try await fileSystem.runInTemporaryDirectory(prefix: "setup") { temporaryPath in
                // Given
                given(configLoader)
                    .loadConfig(path: .any)
                    .willReturn(.test())
                given(serverEnvironmentService)
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
