#if os(macOS)
    import Foundation
    import Testing
    import TuistEnvironmentTesting

    @testable import TuistHTTP

    struct URLSessionIdleConnectionTests {
        @Test(.withMockedEnvironment())
        func configuration_closes_idle_connections_before_the_server_does() {
            let configuration = tuistURLSessionConfiguration()

            #expect(idleConnectionTimeout(of: configuration) == 10)
        }

        @Test(.withMockedEnvironment())
        func shared_session_configures_idle_connections_before_the_server_does() {
            let session = URLSession.tuistShared(useEnvironmentProxy: false)
            defer { session.invalidateAndCancel() }

            #expect(idleConnectionTimeout(of: session.configuration) == 10)
        }
    }
#endif
