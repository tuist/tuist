import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

#if canImport(TuistHAR)
    import TuistHAR
#endif

private func tuistURLSessionConfiguration() -> URLSessionConfiguration {
    let configuration: URLSessionConfiguration = .ephemeral
    configuration.timeoutIntervalForRequest = 120 // 2 minutes
    configuration.timeoutIntervalForResource = 300 // 5 minutes
    #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        configuration.allowsCellularAccess = true
        configuration.allowsConstrainedNetworkAccess = true
        configuration.allowsExpensiveNetworkAccess = true
    #endif
    return configuration
}

#if canImport(TuistHAR)
    private var _tuistURLSession: URLSession = .init(
        configuration: tuistURLSessionConfiguration(),
        delegate: URLSessionMetricsDelegate.shared,
        delegateQueue: nil
    )
#else
    private var _tuistURLSession: URLSession = .init(configuration: tuistURLSessionConfiguration())
#endif

extension URLSession {
    public static var tuistShared: URLSession {
        _tuistURLSession
    }
}
