import Foundation
import Mockable

@Mockable
protocol EndpointLatencyServicing: Sendable {
    func measureLatency(for endpoint: URL) async -> TimeInterval?
}

struct EndpointLatencyService: EndpointLatencyServicing {
    func measureLatency(for endpoint: URL) async -> TimeInterval? {
        let healthCheckURL = endpoint.appendingPathComponent("up")
        var request = URLRequest(url: healthCheckURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 5.0
        request.setValue("no-cache, no-store, must-revalidate", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("0", forHTTPHeaderField: "Expires")

        return await withCheckedContinuation { continuation in
            let delegate = MetricsDelegate(continuation: continuation)
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            delegate.session = session

            Task {
                _ = try? await session.data(for: request)
            }
        }
    }
}

private final class MetricsDelegate: NSObject, URLSessionTaskDelegate {
    private let latencyContinuation: CheckedContinuation<TimeInterval?, Never>
    var session: URLSession?

    init(continuation: CheckedContinuation<TimeInterval?, Never>) {
        latencyContinuation = continuation
        super.init()
    }

    func urlSession(
        _: URLSession,
        task: URLSessionTask,
        didFinishCollecting metrics: URLSessionTaskMetrics
    ) {
        defer {
            session?.invalidateAndCancel()
            session = nil
        }

        // Check if the response status is successful
        if let httpResponse = task.response as? HTTPURLResponse,
           !(200 ... 299).contains(httpResponse.statusCode)
        {
            latencyContinuation.resume(returning: nil)
            return
        }

        guard let transactionMetrics = metrics.transactionMetrics.first,
              let requestStartDate = transactionMetrics.fetchStartDate,
              let responseEndDate = transactionMetrics.responseEndDate
        else {
            latencyContinuation.resume(returning: nil)
            return
        }

        let latency = responseEndDate.timeIntervalSince(requestStartDate)
        latencyContinuation.resume(returning: latency)
    }
}
