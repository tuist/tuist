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

        @Test
        func tuistShared_reuses_sessions_per_proxy_mode() async {
            let previousSettings = HTTPSettings.current
            HTTPSettings.current = .init(useEnvironmentProxy: false)
            defer { HTTPSettings.current = previousSettings }

            let proxied = URLSession.tuistShared(useEnvironmentProxy: true)
            let nonProxied = URLSession.tuistShared(useEnvironmentProxy: false)
            let defaultNonProxied = URLSession.tuistShared

            #expect(ObjectIdentifier(proxied) == ObjectIdentifier(URLSession.tuistShared(useEnvironmentProxy: true)))
            #expect(ObjectIdentifier(nonProxied) == ObjectIdentifier(defaultNonProxied))
            #expect(ObjectIdentifier(proxied) != ObjectIdentifier(nonProxied))
        }
    }
#endif
