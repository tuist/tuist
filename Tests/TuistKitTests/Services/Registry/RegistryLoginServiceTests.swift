import FileSystem
import Foundation
import Mockable
import Testing
import TuistLoader
import TuistServer
import TuistSupport

@testable import TuistKit

struct RegistryLoginServiceTests {
    private let subject: RegistryLoginService
    private let createAccountTokenService = MockCreateAccountTokenServicing()
    private let serverURLService = MockServerURLServicing()
    private let configLoader = MockConfigLoading()
    private let fileSystem = FileSystem()
    private let fullHandleService = MockFullHandleServicing()
    private let swiftPackageManagerController = MockSwiftPackageManagerControlling()
    private let ciChecker = MockCIChecking()
    private let serverAuthenticationController = MockServerAuthenticationControlling()

    init() {
        subject = RegistryLoginService(
            createAccountTokenService: createAccountTokenService,
            serverURLService: serverURLService,
            configLoader: configLoader,
            fileSystem: fileSystem,
            fullHandleService: fullHandleService,
            swiftPackageManagerController: swiftPackageManagerController,
            ciChecker: ciChecker,
            serverAuthenticationController: serverAuthenticationController
        )
    }

    @Test func test_login() async throws {
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
        given(ciChecker)
            .isCI()
            .willReturn(false)
        given(createAccountTokenService)
            .createAccountToken(accountHandle: .any, scopes: .any, serverURL: .any)
            .willReturn("token")
        given(swiftPackageManagerController)
            .packageRegistryLogin(token: .value("token"), registryURL: .any)
            .willReturn()

        // When
        try await subject.run(path: nil)

        // Then
        verify(swiftPackageManagerController)
            .packageRegistryLogin(token: .value("token"), registryURL: .any)
            .called(1)
    }

    @Test func test_login_when_ci() async throws {
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
        given(ciChecker)
            .isCI()
            .willReturn(true)
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("project-token"))
        given(swiftPackageManagerController)
            .packageRegistryLogin(token: .value("project-token"), registryURL: .any)
            .willReturn()

        // When
        try await subject.run(path: nil)

        // Then
        verify(swiftPackageManagerController)
            .packageRegistryLogin(token: .value("project-token"), registryURL: .any)
            .called(1)
    }

    @Test func test_login_when_full_handle_is_missing() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(fullHandle: nil))

        // When/Then
        await #expect(throws: RegistryLoginServiceError.missingFullHandle) {
            try await subject.run(path: nil)
        }
    }
}
