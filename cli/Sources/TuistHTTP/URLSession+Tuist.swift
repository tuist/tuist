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

public func tuistURLSessionConfiguration(useEnvironmentProxy: Bool? = nil) -> URLSessionConfiguration {
    tuistURLSessionConfigurationResolved(useEnvironmentProxy: resolvedUseEnvironmentProxy(useEnvironmentProxy))
}

private func tuistURLSessionConfigurationResolved(useEnvironmentProxy: Bool) -> URLSessionConfiguration {
    let configuration: URLSessionConfiguration = .ephemeral
    configuration.timeoutIntervalForRequest = 120
    configuration.timeoutIntervalForResource = 90
    configuration.httpMaximumConnectionsPerHost = 20
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

private func tuistArtifactTransferURLSessionConfigurationResolved(useEnvironmentProxy: Bool) -> URLSessionConfiguration {
    let configuration = tuistURLSessionConfigurationResolved(useEnvironmentProxy: useEnvironmentProxy)
    // Artifact transfers (shard bundles, cache artifacts) can be hundreds of MB and slow on
    // constrained CI networks. The short resource cap that suits small API calls would kill a
    // healthy-but-slow transfer mid-flight, so allow the whole transfer far more time and let
    // timeoutIntervalForRequest catch genuine stalls (no data) instead.
    configuration.timeoutIntervalForResource = 3600
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

private func makeTuistArtifactTransferURLSession(useEnvironmentProxy: Bool) -> URLSession {
    #if canImport(TuistHAR)
        return URLSession(
            configuration: tuistArtifactTransferURLSessionConfigurationResolved(useEnvironmentProxy: useEnvironmentProxy),
            delegate: URLSessionMetricsDelegate.shared,
            delegateQueue: nil
        )
    #else
        return URLSession(
            configuration: tuistArtifactTransferURLSessionConfigurationResolved(useEnvironmentProxy: useEnvironmentProxy)
        )
    #endif
}

private final class SharedTuistURLSession: @unchecked Sendable {
    private let lock = NSLock()
    private let makeSession: @Sendable (Bool) -> URLSession
    private var useEnvironmentProxy: Bool?
    private var session: URLSession?

    init(makeSession: @escaping @Sendable (Bool) -> URLSession) {
        self.makeSession = makeSession
    }

    func resolve(useEnvironmentProxy: Bool) -> URLSession {
        let sessionToInvalidate: URLSession?
        lock.lock()

        if let session, self.useEnvironmentProxy == useEnvironmentProxy {
            lock.unlock()
            return session
        }

        sessionToInvalidate = session
        let session = makeSession(useEnvironmentProxy)
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

private let sharedTuistURLSession = SharedTuistURLSession(makeSession: makeTuistURLSession)
private let sharedTuistArtifactTransferURLSession =
    SharedTuistURLSession(makeSession: makeTuistArtifactTransferURLSession)

func invalidateSharedTuistURLSession() {
    sharedTuistURLSession.invalidate()
    sharedTuistArtifactTransferURLSession.invalidate()
}

extension URLSession {
    public static var tuistShared: URLSession {
        sharedTuistURLSession.resolve(useEnvironmentProxy: HTTPSettings.current.useEnvironmentProxy)
    }

    public static func tuistShared(useEnvironmentProxy: Bool) -> URLSession {
        makeTuistURLSession(useEnvironmentProxy: useEnvironmentProxy)
    }

    /// A session tuned for large artifact transfers (downloads/uploads of shard bundles, cache
    /// artifacts). Same configuration as `tuistShared` but with a generous resource timeout so a
    /// slow-but-progressing transfer isn't killed by the API-tuned wall-clock cap.
    public static var tuistArtifactTransfer: URLSession {
        sharedTuistArtifactTransferURLSession.resolve(useEnvironmentProxy: HTTPSettings.current.useEnvironmentProxy)
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
