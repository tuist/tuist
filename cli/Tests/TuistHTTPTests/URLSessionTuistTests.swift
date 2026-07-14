#if os(macOS)
    import Foundation
    import Testing
    import TuistEnvironment
    import TuistEnvironmentTesting

    @testable import TuistHTTP

    @Suite(.serialized)
    struct URLSessionTuistTests {
        @Test(.withMockedEnvironment())
        func tuistURLSessionConfiguration_uses_environment_proxy_when_enabled() async throws {
            let environment = try #require(Environment.mocked)
            environment.variables["HTTPS_PROXY"] = "http://proxy.tuist.dev:8080"

            let configuration = tuistURLSessionConfiguration(useEnvironmentProxy: true)
            let proxyHost = configuration.connectionProxyDictionary?[kCFNetworkProxiesHTTPProxy as String] as? String
            let proxyPort = configuration.connectionProxyDictionary?[kCFNetworkProxiesHTTPPort as String] as? Int

            #expect(proxyHost == "proxy.tuist.dev")
            #expect(proxyPort == 8080)
        }

        @Test(.withMockedEnvironment())
        func tuistURLSessionConfiguration_uses_default_timeouts_and_connection_limit() async throws {
            let configuration = tuistURLSessionConfiguration()

            #expect(configuration.timeoutIntervalForRequest == 120)
            #expect(configuration.timeoutIntervalForResource == 90)
            #expect(configuration.httpMaximumConnectionsPerHost == 20)
        }

        @Test(.withMockedEnvironment())
        func tuistURLSessionConfiguration_overrides_timeouts_and_connection_limit_from_environment() async throws {
            let environment = try #require(Environment.mocked)
            environment.variables["TUIST_HTTP_TIMEOUT_INTERVAL_FOR_REQUEST"] = "300"
            environment.variables["TUIST_HTTP_TIMEOUT_INTERVAL_FOR_RESOURCE"] = "600"
            environment.variables["TUIST_HTTP_MAXIMUM_CONNECTIONS_PER_HOST"] = "40"

            let configuration = tuistURLSessionConfiguration()

            #expect(configuration.timeoutIntervalForRequest == 300)
            #expect(configuration.timeoutIntervalForResource == 600)
            #expect(configuration.httpMaximumConnectionsPerHost == 40)
        }

        @Test(.withMockedEnvironment())
        func tuistURLSessionConfiguration_falls_back_to_defaults_for_invalid_environment_values() async throws {
            let environment = try #require(Environment.mocked)
            environment.variables["TUIST_HTTP_TIMEOUT_INTERVAL_FOR_REQUEST"] = "not-a-number"
            environment.variables["TUIST_HTTP_TIMEOUT_INTERVAL_FOR_RESOURCE"] = ""
            environment.variables["TUIST_HTTP_MAXIMUM_CONNECTIONS_PER_HOST"] = "abc"

            let configuration = tuistURLSessionConfiguration()

            #expect(configuration.timeoutIntervalForRequest == 120)
            #expect(configuration.timeoutIntervalForResource == 90)
            #expect(configuration.httpMaximumConnectionsPerHost == 20)
        }

        @Test(.withMockedEnvironment())
        func tuistURLSessionConfiguration_skips_environment_proxy_when_disabled() async throws {
            let environment = try #require(Environment.mocked)
            environment.variables["HTTPS_PROXY"] = "http://proxy.tuist.dev:8080"

            let configuration = tuistURLSessionConfiguration(useEnvironmentProxy: false)

            #expect(configuration.connectionProxyDictionary == nil)
        }

        @Test(.withMockedEnvironment())
        func tuistURLSessionConfiguration_uses_current_http_settings_by_default() async throws {
            let environment = try #require(Environment.mocked)
            environment.variables["HTTPS_PROXY"] = "http://proxy.tuist.dev:8080"

            let previousSettings = HTTPSettings.current
            HTTPSettings.current = .init(useEnvironmentProxy: false)
            defer { HTTPSettings.current = previousSettings }

            let configuration = tuistURLSessionConfiguration()

            #expect(configuration.connectionProxyDictionary == nil)
        }

        @Test(.withMockedEnvironment())
        func tuistShared_resolves_proxy_mode_from_runtime_settings() async throws {
            let environment = try #require(Environment.mocked)
            environment.variables["HTTPS_PROXY"] = "http://proxy.tuist.dev:8080"

            let previousSettings = HTTPSettings.current
            HTTPSettings.current = .init(useEnvironmentProxy: false)
            defer { HTTPSettings.current = previousSettings }

            let defaultSession = URLSession.tuistShared
            let explicitProxiedSession = URLSession.tuistShared(useEnvironmentProxy: true)

            #expect(defaultSession.configuration.connectionProxyDictionary == nil)
            #expect(
                explicitProxiedSession.configuration.connectionProxyDictionary?[kCFNetworkProxiesHTTPProxy as String] as? String
                    == "proxy.tuist.dev"
            )
        }

        @Test(.withMockedEnvironment())
        func tuistShared_reuses_the_process_shared_session() async throws {
            let environment = try #require(Environment.mocked)
            environment.variables["HTTPS_PROXY"] = "http://proxy.tuist.dev:8080"

            let previousSettings = HTTPSettings.current
            HTTPSettings.current = .init(useEnvironmentProxy: false)
            defer { HTTPSettings.current = previousSettings }

            let firstSession = URLSession.tuistShared
            let secondSession = URLSession.tuistShared

            #expect(firstSession === secondSession)
            #expect(firstSession.configuration.connectionProxyDictionary == nil)
        }

        @Test(.withMockedEnvironment())
        func tuistShared_recreates_the_shared_session_when_runtime_settings_change() async throws {
            let environment = try #require(Environment.mocked)
            environment.variables["HTTPS_PROXY"] = "http://proxy.tuist.dev:8080"

            let previousSettings = HTTPSettings.current
            defer { HTTPSettings.current = previousSettings }

            HTTPSettings.current = .init(useEnvironmentProxy: false)
            let firstSession = URLSession.tuistShared

            HTTPSettings.current = .init(useEnvironmentProxy: true)
            let secondSession = URLSession.tuistShared

            #expect(firstSession !== secondSession)
            #expect(firstSession.configuration.connectionProxyDictionary == nil)
            #expect(
                secondSession.configuration.connectionProxyDictionary?[kCFNetworkProxiesHTTPProxy as String] as? String
                    == "proxy.tuist.dev"
            )
        }

        @Test(.withMockedEnvironment())
        func tuistShared_preserves_the_shared_session_when_runtime_settings_are_rewritten_with_the_same_value() async throws {
            let environment = try #require(Environment.mocked)
            environment.variables["HTTPS_PROXY"] = "http://proxy.tuist.dev:8080"

            let previousSettings = HTTPSettings.current
            defer { HTTPSettings.current = previousSettings }

            HTTPSettings.current = .init(useEnvironmentProxy: true)
            let firstSession = URLSession.tuistShared

            HTTPSettings.current = .init(useEnvironmentProxy: true)
            let secondSession = URLSession.tuistShared

            #expect(firstSession === secondSession)
        }
    }
#endif
