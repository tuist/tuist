import FileSystem
import Foundation
import Mockable
import Testing
import TuistLoader
import TuistServerCore
import TuistSupport

@testable import TuistKit

struct RegistryLogoutServiceTests {
    private let serverURLService = MockServerURLServicing()
    private let configLoader = MockConfigLoading()
    private let fileSystem = FileSystem()
    private let swiftPackageManagerController = MockSwiftPackageManagerControlling()
    private let subject: RegistryLogoutService

    init() {
        subject = RegistryLogoutService(
            serverURLService: serverURLService,
            configLoader: configLoader,
            swiftPackageManagerController: swiftPackageManagerController,
            fileSystem: fileSystem
        )
    }

    @Test func test_logout() async throws {
        // Given
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test())
        given(serverURLService)
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
