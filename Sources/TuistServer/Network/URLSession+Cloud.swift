import Foundation

private func cloudURLSessionConfiguration() -> URLSessionConfiguration {
    var configuration: URLSessionConfiguration = .ephemeral
    /**
     Our API design leads to an inefficient usage of the transport layer, which leads to Fly having to spin
     new machines suddenly, and that causes URLSession to time out. The high timeouts here are temporary
     until we change the server-side API to lead to a more efficient using of the transport layer.

     I noticed on Fly https://fly.io/apps/tuist-cloud/metrics that the peaks can reach up to
     100 seconds, hence why I set the limit to 120.
     */
    configuration.timeoutIntervalForRequest = 120 // 2 minutes
    configuration.timeoutIntervalForResource = 300 // 5 minutes
    configuration.allowsCellularAccess = true
    configuration.allowsConstrainedNetworkAccess = true
    configuration.allowsExpensiveNetworkAccess = true
    return configuration
}

private var _cloudURLSession: URLSession = .init(configuration: cloudURLSessionConfiguration())

extension URLSession {
    public static var sharedCloud: URLSession {
        _cloudURLSession
    }
}
