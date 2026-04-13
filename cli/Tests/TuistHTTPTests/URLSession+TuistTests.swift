#if os(macOS)
    import Foundation
    import Testing

    @testable import TuistHTTP

    struct URLSessionTuistProxyTests {
        @Test func resolveProxyURL_returnsNil_whenProxyIsNone() {
            let resolved = resolveProxyURL(for: .none)
            #expect(resolved == nil)
        }

        @Test func resolveProxyURL_returnsExplicitURL_whenProxyIsURL() {
            let url = URL(string: "http://proxy.corp:8080")!
            let resolved = resolveProxyURL(for: .url(url))
            #expect(resolved == url)
        }

        @Test func proxyDictionary_buildsHostPortForExplicitURL() throws {
            let url = URL(string: "http://proxy.corp:8080")!
            let dict = try #require(proxyDictionary(for: .url(url)))
            #expect(dict[kCFNetworkProxiesHTTPProxy as String] as? String == "proxy.corp")
            #expect(dict[kCFNetworkProxiesHTTPPort as String] as? Int == 8080)
            #expect(dict[kCFNetworkProxiesHTTPSProxy as String] as? String == "proxy.corp")
            #expect(dict[kCFNetworkProxiesHTTPSPort as String] as? Int == 8080)
            #expect(dict[kCFNetworkProxiesHTTPEnable as String] as? Int == 1)
            #expect(dict[kCFNetworkProxiesHTTPSEnable as String] as? Int == 1)
        }

        @Test func proxyDictionary_defaultsToPort80ForHttpWithoutExplicitPort() throws {
            let url = URL(string: "http://proxy.corp")!
            let dict = try #require(proxyDictionary(for: .url(url)))
            #expect(dict[kCFNetworkProxiesHTTPPort as String] as? Int == 80)
        }

        @Test func proxyDictionary_defaultsToPort443ForHttpsWithoutExplicitPort() throws {
            let url = URL(string: "https://proxy.corp")!
            let dict = try #require(proxyDictionary(for: .url(url)))
            #expect(dict[kCFNetworkProxiesHTTPPort as String] as? Int == 443)
        }

        @Test func proxyDictionary_returnsNil_whenProxyIsNone() {
            #expect(proxyDictionary(for: .none) == nil)
        }

        @Test func tuistHTTPProxy_equatable() {
            #expect(TuistHTTPProxy.none == TuistHTTPProxy.none)
            let url = URL(string: "http://proxy.corp:8080")!
            #expect(TuistHTTPProxy.url(url) == TuistHTTPProxy.url(url))
            #expect(TuistHTTPProxy.environmentVariable(nil) == TuistHTTPProxy.environmentVariable(nil))
            #expect(TuistHTTPProxy.environmentVariable("FOO") != TuistHTTPProxy.environmentVariable("BAR"))
        }
    }
#endif
