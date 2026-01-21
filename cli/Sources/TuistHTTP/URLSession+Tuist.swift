import Foundation

private func tuistURLSessionConfiguration() -> URLSessionConfiguration {
    let configuration: URLSessionConfiguration = .ephemeral
    configuration.timeoutIntervalForRequest = 120 // 2 minutes
    configuration.timeoutIntervalForResource = 300 // 5 minutes
    configuration.allowsCellularAccess = true
    configuration.allowsConstrainedNetworkAccess = true
    configuration.allowsExpensiveNetworkAccess = true
    return configuration
}

#if os(macOS)
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
