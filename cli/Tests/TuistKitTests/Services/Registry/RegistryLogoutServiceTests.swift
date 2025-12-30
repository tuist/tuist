import FileSystem
import Foundation
import Mockable
import Testing
import TuistLoader
import TuistServer
import TuistSupport

@testable import TuistKit

struct RegistryLogoutServiceTests {
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let configLoader = MockConfigLoading()
    private let fileSystem = FileSystem()
    private let swiftPackageManagerController = MockSwiftPackageManagerControlling()
    private let subject: RegistryLogoutService

    init() {
        subject = RegistryLogoutService(
            serverEnvironmentService: serverEnvironmentService,
            configLoader: configLoader,
            swiftPackageManagerController: swiftPackageManagerController,
            fileSystem: fileSystem
        )
    }

    @Test func logout() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test())
        given(serverEnvironmentService)
            .url(configServerURL: .any)
            .willReturn(.test())
        given(swiftPackageManagerController)
            .packageRegistryLogout(registryURL: .any)
            .willReturn()

        // When
        try await subject.run(path: nil)

        // Then
        verify(swiftPackageManagerController)
            .packageRegistryLogout(registryURL: .any)
            .called(1)
    }
}
