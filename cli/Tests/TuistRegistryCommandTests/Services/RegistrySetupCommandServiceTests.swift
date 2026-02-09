import FileSystem
import Foundation
import Mockable
import Testing
import TuistConfigLoader
import TuistEnvironmentTesting
import TuistNooraTesting
import TuistServer

#if os(macOS)
    import TuistLoader
    import TuistSupport
    import TuistTesting
#endif

@testable import TuistRegistryCommand

struct RegistrySetupCommandServiceTests {
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let configLoader = MockConfigLoading()
    private let fileSystem = FileSystem()

    #if os(macOS)
        private let manifestFilesLocator = MockManifestFilesLocating()
        private let defaultsController = MockDefaultsControlling()
    #endif

    private let subject: RegistrySetupCommandService

    init() {
        #if os(macOS)
            subject = RegistrySetupCommandService(
                serverEnvironmentService: serverEnvironmentService,
                configLoader: configLoader,
                fileSystem: fileSystem,
                manifestFilesLocator: manifestFilesLocator,
                defaultsController: defaultsController
            )

            given(defaultsController)
                .setPackageDendencySCMToRegistryTransformation(.any)
                .willReturn()
        #else
            subject = RegistrySetupCommandService(
                serverEnvironmentService: serverEnvironmentService,
                configLoader: configLoader,
                fileSystem: fileSystem
            )
        #endif
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func setup_when_a_package_manifest_is_found() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: "setup") { temporaryPath in
            // Given
            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(.test())
            let serverURL = URL(string: "https://test.tuist.io")!
            given(serverEnvironmentService)
                .url(configServerURL: .any)
                .willReturn(serverURL)
            #if os(macOS)
                given(manifestFilesLocator)
                    .locatePackageManifest(at: .any)
                    .willProduce { $0.appending(component: "Package.swift") }
            #else
                try await fileSystem.writeText(
                    "// swift-tools-version: 5.9",
                    at: temporaryPath.appending(component: "Package.swift")
                )
            #endif

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
                      "url": "\(serverURL)/api/registry/swift"
                    }
                  },
                  "version": 1
                }

                """
            )
            #if os(macOS)
                verify(defaultsController)
                    .setPackageDendencySCMToRegistryTransformation(.any)
                    .called(0)
            #endif
        }
    }

    @Test(.withMockedEnvironment(), .withMockedNoora)
    func setup_when_a_tuist_package_manifest_is_found() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: "setup") { temporaryPath in
            // Given
            given(configLoader)
                .loadConfig(path: .any)
                .willReturn(.test())
            given(serverEnvironmentService)
                .url(configServerURL: .any)
                .willReturn(URL(string: "https://test.tuist.io")!)
            let tuistDirectory = temporaryPath.appending(component: "Tuist")
            try await fileSystem.makeDirectory(at: tuistDirectory)
            #if os(macOS)
                given(manifestFilesLocator)
                    .locatePackageManifest(at: .any)
                    .willReturn(tuistDirectory.appending(component: "Package.swift"))
            #else
                try await fileSystem.writeText(
                    "// swift-tools-version: 5.9",
                    at: tuistDirectory.appending(component: "Package.swift")
                )
            #endif

            // When
            try await subject.run(path: temporaryPath.pathString)

            // Then
            let configurationPath = tuistDirectory.appending(
                components: ".swiftpm", "configuration", "registries.json"
            )
            let exists = try await fileSystem.exists(configurationPath)
            #expect(exists)
            #if os(macOS)
                verify(defaultsController)
                    .setPackageDendencySCMToRegistryTransformation(.any)
                    .called(0)
            #endif
        }
    }

    #if os(macOS)
        @Test(.withMockedEnvironment(), .withMockedNoora)
        func setup_when_an_xcode_project_is_found() async throws {
            try await fileSystem.runInTemporaryDirectory(prefix: "setup") { temporaryPath in
                // Given
                given(configLoader)
                    .loadConfig(path: .any)
                    .willReturn(.test())
                given(serverEnvironmentService)
                    .url(configServerURL: .any)
                    .willReturn(URL(string: "https://test.tuist.io")!)
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

        @Test(.withMockedEnvironment(), .withMockedNoora)
        func setup_when_an_xcode_workspace_is_found() async throws {
            try await fileSystem.runInTemporaryDirectory(prefix: "setup") { temporaryPath in
                // Given
                given(configLoader)
                    .loadConfig(path: .any)
                    .willReturn(.test())
                given(serverEnvironmentService)
                    .url(configServerURL: .any)
                    .willReturn(URL(string: "https://test.tuist.io")!)
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
    #endif
}
