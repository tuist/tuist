import Foundation

/// A delegate that manages task metrics storage for HAR recording.
public final class URLSessionMetricsDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    /// Shared instance used by the Tuist URLSession.
    public static let shared = URLSessionMetricsDelegate()

    /// Storage for captured metrics, keyed by URL.
    private let metricsStorage = MetricsStorage()

    override private init() {
        super.init()
    }

    // MARK: - URLSessionTaskDelegate

    public func urlSession(_: URLSession, task _: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let transactionMetrics = metrics.transactionMetrics.last,
              let url = transactionMetrics.request.url
        else { return }
        metricsStorage.store(transactionMetrics, for: url)
    }

    // MARK: - Public API

    /// Stores metrics for a URL. Used by TuistURLSessionTransport which captures metrics via per-task delegate.
    /// - Parameters:
    ///   - metrics: The transaction metrics to store.
    ///   - url: The URL to associate with the metrics.
    public func storeMetrics(_ metrics: URLSessionTaskTransactionMetrics, for url: URL) {
        metricsStorage.store(metrics, for: url)
    }

    /// Retrieves and removes the metrics for a URL.
    /// - Parameter url: The URL to look up.
    /// - Returns: The captured metrics, or nil if not found.
    public func retrieveMetrics(for url: URL) -> URLSessionTaskTransactionMetrics? {
        metricsStorage.retrieve(for: url)
    }

    /// Extracts HAR-relevant metadata from URLSessionTaskTransactionMetrics.
    public struct HARMetadata {
        public let timings: HAR.Timings
        public let startTime: Date
        public let endTime: Date
        public let httpVersion: String?
        public let requestHeadersSize: Int?
        public let responseHeadersSize: Int?
    }

    /// Extracts all HAR-relevant metadata from URLSessionTaskTransactionMetrics.
    /// - Parameter metrics: The transaction metrics to extract from.
    /// - Returns: HARMetadata containing timings, dates, and sizes.
    public static func extractHARMetadata(from metrics: URLSessionTaskTransactionMetrics) -> HARMetadata? {
        guard let startTime = metrics.fetchStartDate,
              let endTime = metrics.responseEndDate
        else {
            return nil
        }

        let timings = convertToHARTimings(metrics)
        let httpVersion = metrics.networkProtocolName
        let requestHeadersSize = metrics.countOfRequestHeaderBytesSent > 0
            ? Int(metrics.countOfRequestHeaderBytesSent)
            : nil
        let responseHeadersSize = metrics.countOfResponseHeaderBytesReceived > 0
            ? Int(metrics.countOfResponseHeaderBytesReceived)
            : nil

        return HARMetadata(
            timings: timings,
            startTime: startTime,
            endTime: endTime,
            httpVersion: httpVersion,
            requestHeadersSize: requestHeadersSize,
            responseHeadersSize: responseHeadersSize
        )
    }

    /// Converts URLSessionTaskTransactionMetrics to HAR.Timings.
    /// - Parameter metrics: The transaction metrics to convert.
    /// - Returns: HAR timings with detailed breakdown.
    public static func convertToHARTimings(_ metrics: URLSessionTaskTransactionMetrics) -> HAR.Timings {
        func intervalMs(from start: Date?, to end: Date?) -> Int? {
            guard let start, let end else { return nil }
            let interval = end.timeIntervalSince(start)
            return interval > 0 ? Int(interval * 1000) : 0
        }

        let blocked = intervalMs(from: metrics.fetchStartDate, to: metrics.domainLookupStartDate)
        let dns = intervalMs(from: metrics.domainLookupStartDate, to: metrics.domainLookupEndDate)
        let connect = intervalMs(from: metrics.connectStartDate, to: metrics.connectEndDate)
        let ssl = intervalMs(from: metrics.secureConnectionStartDate, to: metrics.secureConnectionEndDate)
        let send = intervalMs(from: metrics.requestStartDate, to: metrics.requestEndDate) ?? 0
        let wait = intervalMs(from: metrics.requestEndDate, to: metrics.responseStartDate) ?? 0
        let receive = intervalMs(from: metrics.responseStartDate, to: metrics.responseEndDate) ?? 0

        return HAR.Timings(
            blocked: blocked,
            dns: dns,
            connect: connect,
            send: send,
            wait: wait,
            receive: receive,
            ssl: ssl
        )
    }
}

/// Thread-safe storage for URLSession task metrics.
/// Uses FIFO queues per URL to handle concurrent requests to the same endpoint.
private final class MetricsStorage: @unchecked Sendable {
    private var metricsByURL: [URL: [URLSessionTaskTransactionMetrics]] = [:]
    private let lock = NSLock()

    func store(_ metrics: URLSessionTaskTransactionMetrics, for url: URL) {
        lock.lock()
        defer { lock.unlock() }
        metricsByURL[url, default: []].append(metrics)
    }

    func retrieve(for url: URL) -> URLSessionTaskTransactionMetrics? {
        lock.lock()
        defer { lock.unlock() }
        guard var metricsArray = metricsByURL[url], !metricsArray.isEmpty else { return nil }
        let metrics = metricsArray.removeFirst()
        if metricsArray.isEmpty {
            metricsByURL.removeValue(forKey: url)
        } else {
            metricsByURL[url] = metricsArray
        }
        return metrics
    }
}
