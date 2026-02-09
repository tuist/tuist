import Foundation
import Mockable
import Testing
import TuistConfigLoader
import TuistNooraTesting
import TuistServer

@testable import TuistOrganizationCommand

struct OrganizationListServiceTests {
    private let listOrganizationsService: MockListOrganizationsServicing
    private let subject: OrganizationListService
    private let configLoader: MockConfigLoading
    private let serverURL: URL

    init() {
        listOrganizationsService = MockListOrganizationsServicing()
        configLoader = MockConfigLoading()
        serverURL = URL(string: "https://test.tuist.dev")!
        given(configLoader).loadConfig(path: .any).willReturn(.test(url: serverURL))

        subject = OrganizationListService(
            listOrganizationsService: listOrganizationsService,
            configLoader: configLoader
        )
    }

    @Test(.withMockedNoora) func organization_list() async throws {
        // Given
        given(listOrganizationsService).listOrganizations(serverURL: .any)
            .willReturn(
                [
                    "test-one",
                    "test-two",
                ]
            )

        // When
        try await subject.run(json: false, directory: nil)

        // Then
        #expect(
            ui().contains(
                """
                Listing all your organizations:
                  \u{2022} test-one
                  \u{2022} test-two
                """
            )
        )
    }

    @Test(.withMockedNoora) func organization_list_when_none() async throws {
        // Given
        given(listOrganizationsService).listOrganizations(serverURL: .any)
            .willReturn([])

        // When
        try await subject.run(json: false, directory: nil)

        // Then
        #expect(
            ui().contains(
                "You currently have no Cloud organizations. Create one by running `tuist organization create`."
            )
        )
    }
}
