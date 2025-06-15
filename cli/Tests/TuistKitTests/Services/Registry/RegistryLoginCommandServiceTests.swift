import FileSystem
import Foundation
import Mockable
import Testing
import TuistLoader
import TuistServer
import TuistSupport
import TuistTesting

@testable import TuistKit

struct RegistryLoginCommandServiceTests {
    private let subject: RegistryLoginCommandService
    private let createAccountTokenService = MockCreateAccountTokenServicing()
    private let serverURLService = MockServerURLServicing()
    private let configLoader = MockConfigLoading()
    private let fileSystem = FileSystem()
    private let fullHandleService = MockFullHandleServicing()
    private let swiftPackageManagerController = MockSwiftPackageManagerControlling()
    private let serverAuthenticationController = MockServerAuthenticationControlling()
    private let securityController = MockSecurityControlling()
    private let manifestFilesLocator = MockManifestFilesLocating()
    private let defaultsController = MockDefaultsControlling()

    init() {
        subject = RegistryLoginCommandService(
            createAccountTokenService: createAccountTokenService,
            serverURLService: serverURLService,
            configLoader: configLoader,
            fileSystem: fileSystem,
            fullHandleService: fullHandleService,
            swiftPackageManagerController: swiftPackageManagerController,
            serverAuthenticationController: serverAuthenticationController,
            securityController: securityController,
            manifestFilesLocator: manifestFilesLocator,
            defaultsController: defaultsController
        )

        given(defaultsController)
            .setPackageDendencySCMToRegistryTransformation(.any)
            .willReturn()
    }

    @Test(.withMockedEnvironment()) func test_login() async throws {
        try await withMockedDependencies {
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
            let mockEnvironment = try #require(Environment.mocked)
            mockEnvironment.variables = [:]
            given(createAccountTokenService)
                .createAccountToken(accountHandle: .any, scopes: .any, serverURL: .any)
                .willReturn("token")
            given(swiftPackageManagerController)
                .packageRegistryLogin(token: .value("token"), registryURL: .any)
                .willReturn()

            // When
            try await subject.run(path: nil)

            // Then
            #expect(ui().contains("Logged in to the tuist registry") == true)
            verify(swiftPackageManagerController)
                .packageRegistryLogin(token: .value("token"), registryURL: .any)
                .called(1)
            verify(defaultsController)
                .setPackageDendencySCMToRegistryTransformation(
                    .value(.useRegistryIdentityAndSources)
                )
                .called(1)
        }
    }

    @Test(.withMockedEnvironment()) func test_login_when_ci() async throws {
        try await withMockedDependencies {
            try await fileSystem.runInTemporaryDirectory(prefix: "RegistryLoginService") { path in
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
                let mockEnvironment = try #require(Environment.mocked)
                mockEnvironment.variables = ["CI": "1"]
                given(serverAuthenticationController)
                    .authenticationToken(serverURL: .any)
                    .willReturn(.project("project-token"))
                given(swiftPackageManagerController)
                    .packageRegistryLogin(token: .value("project-token"), registryURL: .any)
                    .willReturn()
                given(manifestFilesLocator)
                    .locatePackageManifest(at: .any)
                    .willReturn(path)

                // When
                try await subject.run(path: nil)

                // Then
                verify(swiftPackageManagerController)
                    .packageRegistryLogin(token: .value("project-token"), registryURL: .any)
                    .called(1)
            }
        }
    }

    @Test(.withMockedEnvironment()) func test_login_when_ci_and_xcode_project() async throws {
        try await withMockedDependencies {
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
            let mockEnvironment = try #require(Environment.mocked)
            mockEnvironment.variables = ["CI": "1"]
            given(serverAuthenticationController)
                .authenticationToken(serverURL: .any)
                .willReturn(.project("project-token"))
            given(securityController)
                .addInternetPassword(
                    accountName: .any,
                    serverName: .any,
                    password: .any,
                    securityProtocol: .any,
                    update: .any,
                    applications: .any
                )
                .willReturn()
            given(manifestFilesLocator)
                .locatePackageManifest(at: .any)
                .willReturn(nil)

            // When
            try await subject.run(path: nil)

            // Then
            verify(securityController)
                .addInternetPassword(
                    accountName: .any,
                    serverName: .any,
                    password: .any,
                    securityProtocol: .any,
                    update: .any,
                    applications: .any
                )
                .called(1)
        }
    }

    @Test(.withMockedEnvironment()) func test_login_when_full_handle_is_missing() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: nil))

        // When/Then
        await #expect(throws: RegistryLoginCommandServiceError.missingFullHandle) {
            try await subject.run(path: nil)
        }
    }
}
