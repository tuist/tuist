import Foundation
import Mockable
import Testing
import TuistCAS
import TuistEnvironment
import TuistLoggerTesting
import TuistServer
import TuistTesting

@testable import TuistKit

struct CacheStartCommandServiceTests {
    private let serverURL = URL(string: "https://test.tuist.dev")!
    private let serverEnvironmentService = MockServerEnvironmentServicing()
    private let serverAuthenticationController = MockServerAuthenticationControlling()
    private let cacheURLStore = MockCacheURLStoring()
    private let subject: CacheStartCommandService

    init() {
        subject = CacheStartCommandService(
            serverEnvironmentService: serverEnvironmentService,
            serverAuthenticationController: serverAuthenticationController,
            cacheURLStore: cacheURLStore
        )
    }

    @Test(.withMockedEnvironment(), .withMockedLogger())
    func run_exitsCleanlyWithoutStartingServer_whenNotAuthenticated() async throws {
        // Given
        given(serverEnvironmentService)
            .url()
            .willReturn(serverURL)
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .value(serverURL))
            .willReturn(nil)

        // When
        // A clean return (no thrown error, no started gRPC server) lets the daemon
        // exit with status 0 so the KeepAlive LaunchAgent does not respawn it every
        // ~10 seconds while the user is logged out.
        try await subject.run(fullHandle: "tuist/tuist", url: nil)

        // Then
        verify(cacheURLStore)
            .getCacheURL(for: .any, accountHandle: .any)
            .called(0)
    }
}
