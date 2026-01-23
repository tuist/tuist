import Foundation

/// A URLSession delegate that captures task metrics for HAR recording.
public final class URLSessionMetricsDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    /// Shared instance used by the Tuist URLSession.
    public static let shared = URLSessionMetricsDelegate()

    /// Storage for captured metrics, keyed by task identifier.
    private let metricsStorage = MetricsStorage()

    override private init() {
        super.init()
    }

    // MARK: - URLSessionTaskDelegate

    public func urlSession(_: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let transactionMetrics = metrics.transactionMetrics.last else { return }
        metricsStorage.store(transactionMetrics, for: task.taskIdentifier)
    }

    // MARK: - Public API

    /// Retrieves and removes the metrics for a given task identifier.
    /// - Parameter taskIdentifier: The task identifier to look up.
    /// - Returns: The captured metrics, or nil if not found.
    public func retrieveMetrics(for taskIdentifier: Int) -> URLSessionTaskTransactionMetrics? {
        metricsStorage.retrieve(for: taskIdentifier)
    }

    /// Retrieves metrics for a URL and removes them from storage.
    /// This is useful when the task identifier is not available.
    /// - Parameter url: The URL to look up.
    /// - Returns: The captured metrics, or nil if not found.
    public func retrieveMetrics(for url: URL) -> URLSessionTaskTransactionMetrics? {
        metricsStorage.retrieve(for: url)
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
private final class MetricsStorage: @unchecked Sendable {
    private var metricsByTaskId: [Int: URLSessionTaskTransactionMetrics] = [:]
    private var metricsByURL: [URL: URLSessionTaskTransactionMetrics] = [:]
    private let lock = NSLock()

    func store(_ metrics: URLSessionTaskTransactionMetrics, for taskIdentifier: Int) {
        lock.lock()
        defer { lock.unlock() }
        metricsByTaskId[taskIdentifier] = metrics
        if let url = metrics.request.url {
            metricsByURL[url] = metrics
        }
    }

    func retrieve(for taskIdentifier: Int) -> URLSessionTaskTransactionMetrics? {
        lock.lock()
        defer { lock.unlock() }
        let metrics = metricsByTaskId.removeValue(forKey: taskIdentifier)
        if let url = metrics?.request.url {
            metricsByURL.removeValue(forKey: url)
        }
        return metrics
    }

    func retrieve(for url: URL) -> URLSessionTaskTransactionMetrics? {
        lock.lock()
        defer { lock.unlock() }
        guard let metrics = metricsByURL.removeValue(forKey: url) else { return nil }
        if let taskId = findTaskId(for: metrics) {
            metricsByTaskId.removeValue(forKey: taskId)
        }
        return metrics
    }

    private func findTaskId(for metrics: URLSessionTaskTransactionMetrics) -> Int? {
        for (taskId, storedMetrics) in metricsByTaskId {
            if storedMetrics === metrics {
                return taskId
            }
        }
        return nil
    }
}
