import Foundation
import TuistEnvironment
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

#if canImport(TuistHAR)
    import TuistHAR
#endif

private func environmentProxyURL() -> URL? {
    let environment = Environment.current.variables
    let candidates = ["HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy"]
    for key in candidates {
        if let value = environment[key], !value.isEmpty, let url = URL(string: value) {
            return url
        }
    }
    return nil
}

private func resolvedUseEnvironmentProxy(_ useEnvironmentProxy: Bool?) -> Bool {
    useEnvironmentProxy ?? HTTPSettings.current.useEnvironmentProxy
}

private func environmentInt(_ key: String, default defaultValue: Int) -> Int {
    guard let value = Environment.current.variables[key], let parsed = Int(value) else {
        return defaultValue
    }
    return parsed
}

public func tuistURLSessionConfiguration(useEnvironmentProxy: Bool? = nil) -> URLSessionConfiguration {
    tuistURLSessionConfigurationResolved(useEnvironmentProxy: resolvedUseEnvironmentProxy(useEnvironmentProxy))
}

private func tuistURLSessionConfigurationResolved(useEnvironmentProxy: Bool) -> URLSessionConfiguration {
    let configuration: URLSessionConfiguration = .ephemeral
    configuration.timeoutIntervalForRequest = Double(environmentInt("TUIST_HTTP_TIMEOUT_INTERVAL_FOR_REQUEST", default: 120))
    configuration.timeoutIntervalForResource = Double(environmentInt("TUIST_HTTP_TIMEOUT_INTERVAL_FOR_RESOURCE", default: 90))
    configuration.httpMaximumConnectionsPerHost = environmentInt("TUIST_HTTP_MAXIMUM_CONNECTIONS_PER_HOST", default: 20)
    #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        configuration.allowsCellularAccess = true
        configuration.allowsConstrainedNetworkAccess = true
        configuration.allowsExpensiveNetworkAccess = true
    #endif
    #if os(macOS)
        if useEnvironmentProxy,
           let proxyURL = environmentProxyURL(),
           let dictionary = proxyDictionary(for: proxyURL)
        {
            configuration.connectionProxyDictionary = dictionary
        }
    #endif
    return configuration
}

private func makeTuistURLSession(useEnvironmentProxy: Bool) -> URLSession {
    #if canImport(TuistHAR)
        return URLSession(
            configuration: tuistURLSessionConfigurationResolved(useEnvironmentProxy: useEnvironmentProxy),
            delegate: URLSessionMetricsDelegate.shared,
            delegateQueue: nil
        )
    #else
        return URLSession(configuration: tuistURLSessionConfigurationResolved(useEnvironmentProxy: useEnvironmentProxy))
    #endif
}

private final class SharedTuistURLSession: @unchecked Sendable {
    private let make: @Sendable (Bool) -> URLSession
    private let lock = NSLock()
    private var useEnvironmentProxy: Bool?
    private var session: URLSession?

    init(make: @escaping @Sendable (Bool) -> URLSession) {
        self.make = make
    }

    func resolve(useEnvironmentProxy: Bool) -> URLSession {
        let sessionToInvalidate: URLSession?
        lock.lock()

        if let session, self.useEnvironmentProxy == useEnvironmentProxy {
            lock.unlock()
            return session
        }

        sessionToInvalidate = session
        let session = make(useEnvironmentProxy)
        self.useEnvironmentProxy = useEnvironmentProxy
        self.session = session
        lock.unlock()
        sessionToInvalidate?.invalidateAndCancel()
        return session
    }

    func invalidate() {
        let sessionToInvalidate: URLSession?
        lock.lock()
        useEnvironmentProxy = nil
        sessionToInvalidate = session
        session = nil
        lock.unlock()
        sessionToInvalidate?.invalidateAndCancel()
    }
}

/// The CAS hot path fires thousands of requests per build. A short inactivity
/// timeout makes a hung cache backend surface in seconds (the CAS circuit breaker
/// then skips it for the rest of the build) instead of every compilation unit
/// stalling on the default 90s; the resource timeout stays generous so a large but
/// progressing artifact transfer is not cut off.
private func makeTuistCASURLSession(useEnvironmentProxy: Bool) -> URLSession {
    let configuration = tuistURLSessionConfigurationResolved(useEnvironmentProxy: useEnvironmentProxy)
    configuration.timeoutIntervalForRequest = 15
    configuration.timeoutIntervalForResource = 300
    #if canImport(TuistHAR)
        return URLSession(configuration: configuration, delegate: URLSessionMetricsDelegate.shared, delegateQueue: nil)
    #else
        return URLSession(configuration: configuration)
    #endif
}

private let sharedTuistURLSession = SharedTuistURLSession { makeTuistURLSession(useEnvironmentProxy: $0) }
private let sharedTuistCASURLSession = SharedTuistURLSession { makeTuistCASURLSession(useEnvironmentProxy: $0) }

func invalidateSharedTuistURLSession() {
    sharedTuistURLSession.invalidate()
    sharedTuistCASURLSession.invalidate()
}

extension URLSession {
    public static var tuistShared: URLSession {
        sharedTuistURLSession.resolve(useEnvironmentProxy: HTTPSettings.current.useEnvironmentProxy)
    }

    public static func tuistShared(useEnvironmentProxy: Bool) -> URLSession {
        makeTuistURLSession(useEnvironmentProxy: useEnvironmentProxy)
    }

    /// A shared session tuned for the CAS hot path: a short inactivity timeout so
    /// a hung backend fails fast rather than stalling every compilation unit.
    /// Resolves the current proxy setting like `tuistShared`, so a proxy change is
    /// picked up rather than pinned to first use.
    public static var tuistCAS: URLSession {
        sharedTuistCASURLSession.resolve(useEnvironmentProxy: HTTPSettings.current.useEnvironmentProxy)
    }
}

#if os(macOS)
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
