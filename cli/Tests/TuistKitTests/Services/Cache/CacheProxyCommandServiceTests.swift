import Foundation
import Mockable
import Testing
import TuistCAS
import TuistEnvironment
import TuistEnvironmentTesting
import TuistLoader
import TuistServer

@testable import TuistKit

struct CacheProxyCommandServiceTests {
    @Test(.withMockedEnvironment(), arguments: ["https://cache.example", "https://acme.cache.tuist.dev"])
    func network_trusted_startup_validates_the_resolved_cache_destination(endpoint: String) async throws {
        let environment = try #require(Environment.mocked)
        environment.variables = [:]
        let serverURL = try #require(URL(string: "https://tuist.example"))
        let authentication = MockServerAuthenticationControlling()
        given(authentication).authenticationToken(serverURL: .any).willReturn(nil)
        let serverEnvironment = MockServerEnvironmentServicing()
        given(serverEnvironment).url(configServerURL: .any).willReturn(serverURL)
        let store = MockCacheURLStoring()
        given(store).getCacheURL(for: .any, accountHandle: .any).willReturn(try #require(URL(string: endpoint)))
        let service = CacheProxyCommandService(
            serverEnvironmentService: serverEnvironment,
            serverAuthenticationController: authentication,
            cacheURLStore: store,
            resourceLocator: MockResourceLocator()
        )
        try await ServerCacheAccessMode.$serverAllowsNetworkCacheAccess.withValue({ _ in true }) {
            if endpoint == "https://cache.example" {
                await #expect(throws: CacheProxyCommandServiceError.proxyBinaryMissing) {
                    try await service.run(url: serverURL.absoluteString, accountHandle: "acme")
                }
            } else {
                await #expect(throws: ServerReportPublishingError.selfHostedDestinationRequired) {
                    try await service.run(url: serverURL.absoluteString, accountHandle: "acme")
                }
            }
        }
    }

    @Test(.withMockedEnvironment())
    func missing_discovered_endpoint_starts_local_only() async throws {
        let environment = try #require(Environment.mocked)
        environment.variables = [:]
        let service = MockGetCacheEndpointServicing()
        given(service).getCacheEndpoint(serverURL: .any)
            .willReturn(CacheEndpointResolution(endpoint: nil, maxAge: 5))
        let store = CacheURLStore(getCacheEndpointService: service, configurationCache: CachedValueStore())
        let endpoint = try await CacheProxyCommandService(cacheURLStore: store).remoteEndpoint(
            serverURL: URL(string: "http://localhost:8080")!, accountHandle: "account"
        )
        #expect(endpoint == nil)
    }

    @Test func spawn_startsTheExecutableWithSIGTERMUnblockedFromAConcurrencyThread() async throws {
        let (callerBlocksSIGTERM, processIdentifier) = try await Task.detached {
            var mask = sigset_t()
            pthread_sigmask(SIG_SETMASK, nil, &mask)
            let processIdentifier = try CacheProxyCommandService.spawn(
                executable: "/bin/sh",
                arguments: ["-c", "kill -TERM $$; exit 0"]
            )
            return (sigismember(&mask, SIGTERM) == 1, processIdentifier)
        }.value

        var status: Int32 = 0
        waitpid(processIdentifier, &status, 0)

        #expect(callerBlocksSIGTERM, "the spawn must run where the proxy's handoff runs, on a thread that blocks SIGTERM")
        #expect(status & 0x7F == SIGTERM, "the child exited with status \(status) instead of being terminated by SIGTERM")
    }
}
