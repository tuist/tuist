#if os(macOS)
    import Foundation
    import Testing

    @testable import TuistHTTP

    struct URLSessionTuistProxyTests {
        @Test func proxyDictionary_buildsHostPortForExplicitURL() throws {
            let url = URL(string: "http://proxy.corp:8080")!
            let dict = try #require(proxyDictionary(for: url))
            #expect(dict[kCFNetworkProxiesHTTPProxy as String] as? String == "proxy.corp")
            #expect(dict[kCFNetworkProxiesHTTPPort as String] as? Int == 8080)
            #expect(dict[kCFNetworkProxiesHTTPSProxy as String] as? String == "proxy.corp")
            #expect(dict[kCFNetworkProxiesHTTPSPort as String] as? Int == 8080)
            #expect(dict[kCFNetworkProxiesHTTPEnable as String] as? Int == 1)
            #expect(dict[kCFNetworkProxiesHTTPSEnable as String] as? Int == 1)
        }

        @Test func proxyDictionary_defaultsToPort80ForHttpWithoutExplicitPort() throws {
            let url = URL(string: "http://proxy.corp")!
            let dict = try #require(proxyDictionary(for: url))
            #expect(dict[kCFNetworkProxiesHTTPPort as String] as? Int == 80)
        }

        @Test func proxyDictionary_defaultsToPort443ForHttpsWithoutExplicitPort() throws {
            let url = URL(string: "https://proxy.corp")!
            let dict = try #require(proxyDictionary(for: url))
            #expect(dict[kCFNetworkProxiesHTTPPort as String] as? Int == 443)
        }

        @Test func proxyDictionary_returnsNilWhenURLHasNoHost() {
            // A path-only URL has no host — `proxyDictionary` can't do anything useful.
            let url = URL(string: "/just/a/path")!
            #expect(proxyDictionary(for: url) == nil)
        }
    }
#endif
