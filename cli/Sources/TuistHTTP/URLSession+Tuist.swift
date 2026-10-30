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

/// Resolves the path to a custom CA certificate bundle. The `TUIST_CA_CERTIFICATE`
/// environment variable takes precedence over the value declared in the config so it
/// can be supplied as a CI secret without changing the committed manifest.
private func resolvedCACertificatePath() -> String? {
    let environment = Environment.current.variables
    if let value = environment["TUIST_CA_CERTIFICATE"], !value.isEmpty {
        return value
    }
    return HTTPSettings.current.caCertificatePath
}

/// Apple sessions always apply the key deny after normal trust evaluation, even
/// without a custom CA bundle. Additional anchors augment the system roots. Other
/// platforms keep their metrics behavior and require separate verifier qualification.
private func tuistSessionDelegate(
    additionalBlockedSPKIHashes: Set<String>, followRedirects: Bool
) -> (URLSessionDelegate & URLSessionTaskDelegate)? {
    #if canImport(Security)
        let certificates = resolvedCACertificatePath().flatMap { CACertificateLoader.load(from: $0) } ?? []
        return TuistURLSessionDelegate(
            additionalCertificates: certificates,
            additionalBlockedSPKIHashes: additionalBlockedSPKIHashes,
            followRedirects: followRedirects
        )
    #else
        if !followRedirects { return NoDiscoveryRedirects() }
        #if canImport(TuistHAR)
            return URLSessionMetricsDelegate.shared
        #else
            return nil
        #endif
    #endif
}

private func makeURLSession(
    configuration: URLSessionConfiguration, additionalBlockedSPKIHashes: Set<String> = [], followRedirects: Bool = true
) -> URLSession {
    if let delegate = tuistSessionDelegate(
        additionalBlockedSPKIHashes: additionalBlockedSPKIHashes, followRedirects: followRedirects
    ) {
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }
    return URLSession(configuration: configuration)
}

private func environmentInt(_ key: String, default defaultValue: Int) -> Int {
    guard let value = Environment.current.variables[key], let parsed = Int(value) else {
        return defaultValue
    }
    return parsed
}

/// Below the 15-second idle timeout the server applies to keep-alive connections, so the client
/// closes an idle connection before the server can close it under a request being written.
let tuistIdleConnectionTimeout: TimeInterval = 10

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
    private let idleConnectionTimeoutKey = "_connectionCachePurgeTimeout"

    private func setIdleConnectionTimeout(_ timeout: TimeInterval, on configuration: URLSessionConfiguration) {
        guard configuration.responds(to: NSSelectorFromString("set\(idleConnectionTimeoutKey):")) else { return }
        configuration.setValue(timeout, forKey: idleConnectionTimeoutKey)
    }

    func idleConnectionTimeout(of configuration: URLSessionConfiguration) -> TimeInterval? {
        guard configuration.responds(to: NSSelectorFromString(idleConnectionTimeoutKey)) else { return nil }
        return configuration.value(forKey: idleConnectionTimeoutKey) as? TimeInterval
    }
#endif

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
        setIdleConnectionTimeout(tuistIdleConnectionTimeout, on: configuration)
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
    makeURLSession(configuration: tuistURLSessionConfigurationResolved(useEnvironmentProxy: useEnvironmentProxy))
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
    return makeURLSession(configuration: configuration)
}

/// The floor on how long a whole-file transfer may take. 10 minutes clears a 3GB archive at 40Mbps.
private let largeTransferResourceTimeout = 600

/// A single transfer here can be several gigabytes, such as a shard's test products. The resource
/// timeout is a wall-clock cap on the whole transfer rather than a stall guard, so the 90s default
/// cancels transfers that are progressing normally: finishing 3GB within it requires a sustained
/// ~270Mbps. The inactivity timeout is the stall guard instead, and the wall-clock cap is only a
/// backstop against a transfer that trickles.
///
/// The two sessions want `TUIST_HTTP_TIMEOUT_INTERVAL_FOR_RESOURCE` to move in opposite directions:
/// lowering it makes a starved cache request fail fast into a local build, which would put these
/// transfers back under a cap they cannot meet. It is therefore honored only upward here, so a job
/// tuning the cache path cannot reintroduce the timeout this floor exists to prevent.
private func makeTuistLargeTransferURLSession(useEnvironmentProxy: Bool) -> URLSession {
    let configuration = tuistURLSessionConfigurationResolved(useEnvironmentProxy: useEnvironmentProxy)
    configuration.timeoutIntervalForResource = Double(
        max(
            environmentInt("TUIST_HTTP_TIMEOUT_INTERVAL_FOR_RESOURCE", default: largeTransferResourceTimeout),
            largeTransferResourceTimeout
        )
    )
    return makeURLSession(configuration: configuration)
}

private let sharedTuistURLSession = SharedTuistURLSession { makeTuistURLSession(useEnvironmentProxy: $0) }
private let sharedTuistCASURLSession = SharedTuistURLSession { makeTuistCASURLSession(useEnvironmentProxy: $0) }
private let sharedTuistLargeTransferURLSession = SharedTuistURLSession {
    makeTuistLargeTransferURLSession(useEnvironmentProxy: $0)
}

func invalidateSharedTuistURLSession() {
    sharedTuistURLSession.invalidate()
    sharedTuistCASURLSession.invalidate()
    sharedTuistLargeTransferURLSession.invalidate()
}

private final class NoDiscoveryRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _: URLSession, task _: URLSessionTask, willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    #if canImport(TuistHAR)
        func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
            URLSessionMetricsDelegate.shared.urlSession(session, task: task, didFinishCollecting: metrics)
        }
    #endif
}

extension URLSession {
    /// Retains native default cache, cookie and timeout behavior for direct callers.
    /// Apple platforms add the key policy; other platforms require a patched verifier.
    public static let tuistDefault = makeURLSession(configuration: .default)

    /// Retains caller-supplied cache/timeouts and installs the key policy on Apple.
    /// Other platforms require independent qualification of the native verifier.
    public static func tuist(configuration: URLSessionConfiguration) -> URLSession {
        makeURLSession(configuration: configuration)
    }

    #if canImport(Security)
        /// Adds restrictions without allowing removal of the embedded key policy.
        public static func tuist(configuration: URLSessionConfiguration, additionalBlockedSPKIHashes: Set<String>) -> URLSession {
            makeURLSession(configuration: configuration, additionalBlockedSPKIHashes: additionalBlockedSPKIHashes)
        }
    #endif

    public static var tuistDiscovery: URLSession {
        let configuration = tuistURLSessionConfiguration()
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        return makeURLSession(configuration: configuration, followRedirects: false)
    }

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

    /// A shared session for transfers of whole artifacts, which are large enough that
    /// `tuistShared`'s wall-clock resource timeout cancels healthy transfers.
    public static var tuistLargeTransfer: URLSession {
        sharedTuistLargeTransferURLSession.resolve(useEnvironmentProxy: HTTPSettings.current.useEnvironmentProxy)
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
