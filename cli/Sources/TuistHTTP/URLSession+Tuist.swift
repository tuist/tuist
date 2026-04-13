import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

#if canImport(TuistHAR)
    import TuistHAR
#endif

private let _sessionLock = NSLock()
nonisolated(unsafe) private var _currentProxyURL: URL? = nil
nonisolated(unsafe) private var _tuistURLSession: URLSession = makeTuistURLSession(proxyURL: nil)

private func tuistURLSessionConfiguration(proxyURL: URL?) -> URLSessionConfiguration {
    let configuration: URLSessionConfiguration = .ephemeral
    configuration.timeoutIntervalForRequest = 120 // 2 minutes
    configuration.timeoutIntervalForResource = 300 // 5 minutes
    configuration.httpMaximumConnectionsPerHost = 20
    #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        configuration.allowsCellularAccess = true
        configuration.allowsConstrainedNetworkAccess = true
        configuration.allowsExpensiveNetworkAccess = true
    #endif
    #if os(macOS)
        if let proxyURL, let dictionary = proxyDictionary(for: proxyURL) {
            configuration.connectionProxyDictionary = dictionary
        }
    #endif
    return configuration
}

private func makeTuistURLSession(proxyURL: URL?) -> URLSession {
    #if canImport(TuistHAR)
        return URLSession(
            configuration: tuistURLSessionConfiguration(proxyURL: proxyURL),
            delegate: URLSessionMetricsDelegate.shared,
            delegateQueue: nil
        )
    #else
        return URLSession(configuration: tuistURLSessionConfiguration(proxyURL: proxyURL))
    #endif
}

extension URLSession {
    public static var tuistShared: URLSession {
        _sessionLock.lock()
        defer { _sessionLock.unlock() }
        return _tuistURLSession
    }

    /// Configures the HTTP proxy URL used by `URLSession.tuistShared`. Pass `nil` to
    /// disable the proxy.
    ///
    /// Callers are expected to have already resolved their user-facing proxy configuration
    /// (e.g. `.environmentVariable("HTTPS_PROXY")`) into a concrete URL before reaching this
    /// function — the HTTP layer intentionally does not know about env variables.
    public static func configureTuistProxy(_ proxyURL: URL?) {
        _sessionLock.lock()
        defer { _sessionLock.unlock() }
        guard proxyURL != _currentProxyURL else { return }
        _currentProxyURL = proxyURL
        _tuistURLSession = makeTuistURLSession(proxyURL: proxyURL)
    }
}

#if os(macOS)
    /// Builds a `connectionProxyDictionary` compatible with `URLSessionConfiguration`
    /// for the given proxy URL, or `nil` when the URL has no host.
    func proxyDictionary(for proxyURL: URL) -> [AnyHashable: Any]? {
        guard let host = proxyURL.host else { return nil }
        let port = proxyURL.port ?? defaultProxyPort(for: proxyURL.scheme)
        var dictionary: [AnyHashable: Any] = [:]
        dictionary[kCFNetworkProxiesHTTPEnable as String] = 1
        dictionary[kCFNetworkProxiesHTTPProxy as String] = host
        dictionary[kCFNetworkProxiesHTTPPort as String] = port
        dictionary[kCFNetworkProxiesHTTPSEnable as String] = 1
        dictionary[kCFNetworkProxiesHTTPSProxy as String] = host
        dictionary[kCFNetworkProxiesHTTPSPort as String] = port
        return dictionary
    }

    private func defaultProxyPort(for scheme: String?) -> Int {
        switch scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return 8080
        }
    }
#endif
