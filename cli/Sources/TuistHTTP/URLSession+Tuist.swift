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
    configuration.timeoutIntervalForResource = 300
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

extension URLSession {
    public static var tuistShared: URLSession {
        makeTuistURLSession(useEnvironmentProxy: HTTPSettings.current.useEnvironmentProxy)
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
