import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

#if canImport(TuistHAR)
    import TuistHAR
#endif

/// Proxy configuration for Tuist's shared URLSession.
///
/// Mirrors `TuistConfig.Tuist.Proxy` but lives in TuistHTTP so that lower-level networking
/// code does not need to depend on the config module. The translation happens at the
/// boundary when the CLI loads its configuration.
public enum TuistHTTPProxy: Equatable, Sendable {
    /// No proxy. Tuist makes direct connections.
    case none

    /// Read the proxy URL from an environment variable.
    ///
    /// When `name` is `nil`, Tuist reads `HTTPS_PROXY` and falls back to `HTTP_PROXY`.
    /// Both uppercase and lowercase variants are checked.
    case environmentVariable(String?)

    /// Use the given proxy URL directly.
    case url(URL)
}

private let _sessionLock = NSLock()
nonisolated(unsafe) private var _currentProxy: TuistHTTPProxy = .none
nonisolated(unsafe) private var _tuistURLSession: URLSession = makeTuistURLSession(proxy: .none)

private func tuistURLSessionConfiguration(proxy: TuistHTTPProxy) -> URLSessionConfiguration {
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
        if let dictionary = proxyDictionary(for: proxy) {
            configuration.connectionProxyDictionary = dictionary
        }
    #endif
    return configuration
}

private func makeTuistURLSession(proxy: TuistHTTPProxy) -> URLSession {
    #if canImport(TuistHAR)
        return URLSession(
            configuration: tuistURLSessionConfiguration(proxy: proxy),
            delegate: URLSessionMetricsDelegate.shared,
            delegateQueue: nil
        )
    #else
        return URLSession(configuration: tuistURLSessionConfiguration(proxy: proxy))
    #endif
}

extension URLSession {
    public static var tuistShared: URLSession {
        _sessionLock.lock()
        defer { _sessionLock.unlock() }
        return _tuistURLSession
    }

    /// Configures the HTTP proxy used by `URLSession.tuistShared`.
    ///
    /// Call this once, early in the lifecycle (e.g., right after loading `Tuist.swift`),
    /// before any network requests are made. Subsequent calls with a different proxy
    /// rebuild the shared session.
    public static func configureTuistProxy(_ proxy: TuistHTTPProxy) {
        _sessionLock.lock()
        defer { _sessionLock.unlock() }
        guard proxy != _currentProxy else { return }
        _currentProxy = proxy
        _tuistURLSession = makeTuistURLSession(proxy: proxy)
    }
}

#if os(macOS)
    /// Resolves the proxy URL for the given configuration and builds a
    /// `connectionProxyDictionary` compatible with `URLSessionConfiguration`.
    ///
    /// Returns `nil` when the configuration resolves to no proxy (including the case where
    /// the configured environment variable is not set).
    func proxyDictionary(for proxy: TuistHTTPProxy) -> [AnyHashable: Any]? {
        guard let url = resolveProxyURL(for: proxy), let host = url.host else {
            return nil
        }
        let port = url.port ?? defaultProxyPort(for: url.scheme)
        var dictionary: [AnyHashable: Any] = [:]
        dictionary[kCFNetworkProxiesHTTPEnable as String] = 1
        dictionary[kCFNetworkProxiesHTTPProxy as String] = host
        dictionary[kCFNetworkProxiesHTTPPort as String] = port
        dictionary[kCFNetworkProxiesHTTPSEnable as String] = 1
        dictionary[kCFNetworkProxiesHTTPSProxy as String] = host
        dictionary[kCFNetworkProxiesHTTPSPort as String] = port
        return dictionary
    }

    func resolveProxyURL(for proxy: TuistHTTPProxy) -> URL? {
        switch proxy {
        case .none:
            return nil
        case let .url(url):
            return url
        case let .environmentVariable(name):
            guard let value = resolveProxyEnvironmentValue(name: name) else {
                return nil
            }
            return URL(string: value)
        }
    }

    private func resolveProxyEnvironmentValue(name: String?) -> String? {
        let env = ProcessInfo.processInfo.environment
        if let name {
            let value = env[name]
            return (value?.isEmpty == false) ? value : nil
        }
        let candidates = ["HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy"]
        for candidate in candidates {
            if let value = env[candidate], !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func defaultProxyPort(for scheme: String?) -> Int {
        switch scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return 8080
        }
    }
#endif
