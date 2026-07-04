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
    // The resource timeout caps the WHOLE transfer, connection-pool queueing
    // included, so it must comfortably exceed the request (idle) timeout: large
    // cache artifacts queued behind httpMaximumConnectionsPerHost were killed
    // mid-upload at the previous 90s cap and surfaced as "The network
    // connection was lost". Stalls are still bounded by the request timeout.
    configuration.timeoutIntervalForResource = Double(environmentInt("TUIST_HTTP_TIMEOUT_INTERVAL_FOR_RESOURCE", default: 3600))
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
    private let lock = NSLock()
    private var useEnvironmentProxy: Bool?
    private var session: URLSession?

    func resolve(useEnvironmentProxy: Bool) -> URLSession {
        let sessionToInvalidate: URLSession?
        lock.lock()

        if let session, self.useEnvironmentProxy == useEnvironmentProxy {
            lock.unlock()
            return session
        }

        sessionToInvalidate = session
        let session = makeTuistURLSession(useEnvironmentProxy: useEnvironmentProxy)
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

private let sharedTuistURLSession = SharedTuistURLSession()

func invalidateSharedTuistURLSession() {
    sharedTuistURLSession.invalidate()
}

extension URLSession {
    public static var tuistShared: URLSession {
        sharedTuistURLSession.resolve(useEnvironmentProxy: HTTPSettings.current.useEnvironmentProxy)
    }

    public static func tuistShared(useEnvironmentProxy: Bool) -> URLSession {
        makeTuistURLSession(useEnvironmentProxy: useEnvironmentProxy)
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
