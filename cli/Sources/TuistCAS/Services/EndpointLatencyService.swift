import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import Mockable
import TuistHTTP

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

        #if os(macOS)
            // Use URLSessionTaskMetrics for precise timing on macOS. Route through the
            // shared session so a configured CA certificate bundle is honored when probing
            // private-CA endpoints; the metrics are captured via a per-task delegate.
            return await withCheckedContinuation { continuation in
                let delegate = MetricsDelegate(continuation: continuation)
                Task {
                    _ = try? await URLSession.tuistShared.data(for: request, delegate: delegate)
                }
            }
        #else
            // URLSessionTaskMetrics is not available on Linux:
            // https://github.com/swiftlang/swift-corelibs-foundation/issues/4988
            let clock = ContinuousClock()
            let start = clock.now
            do {
                let (_, response) = try await URLSession.tuistShared.data(for: request)
                let end = clock.now
                let duration = end - start
                if let httpResponse = response as? HTTPURLResponse,
                   (200 ... 299).contains(httpResponse.statusCode)
                {
                    let seconds = Double(duration.components.seconds)
                    let attoseconds = Double(duration.components.attoseconds) / 1_000_000_000_000_000_000
                    return seconds + attoseconds
                }
                return nil
            } catch {
                return nil
            }
        #endif
    }
}

#if os(macOS)
    private final class MetricsDelegate: NSObject, URLSessionTaskDelegate {
        private let latencyContinuation: CheckedContinuation<TimeInterval?, Never>

        init(continuation: CheckedContinuation<TimeInterval?, Never>) {
            latencyContinuation = continuation
            super.init()
        }

        func urlSession(
            _: URLSession,
            task: URLSessionTask,
            didFinishCollecting metrics: URLSessionTaskMetrics
        ) {
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
#endif
