import Foundation
import Mockable
import Testing
import TuistCAS
import TuistEnvironment
import TuistEnvironmentTesting
import TuistServer

@testable import TuistKit

struct CacheProxyCommandServiceTests {
    @Test(.withMockedEnvironment())
    func missing_discovered_endpoint_starts_local_only() async throws {
        let environment = try #require(Environment.mocked)
        environment.variables = [:]
        let service = MockGetCacheEndpointsServicing()
        given(service).getCacheEndpoints(serverURL: .any, accountHandle: .any)
            .willReturn(CacheEndpointsResolution(endpoints: [], maxAge: 5))
        let store = CacheURLStore(getCacheEndpointsService: service, configurationCache: CachedValueStore())
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
