import Foundation
import Path
import TuistSupport

/// An actor that manages HAR recording and persistence.
public actor HARRecorder {
    /// The current HAR recorder instance for the session.
    @TaskLocal public static var current: HARRecorder?

    /// Headers that should be redacted for security reasons.
    public static let sensitiveHeaders: Set<String> = [
        "authorization",
        "cookie",
        "set-cookie",
        "x-api-key",
        "x-auth-token",
        "x-access-token",
        "proxy-authorization",
        "www-authenticate",
        "x-amz-security-token",
        "x-amz-credential",
    ]

    private var log: HAR.Log
    private let filePath: AbsolutePath?

    /// Creates a new HAR recorder.
    /// - Parameters:
    ///   - filePath: The path where the HAR file will be saved. If nil, entries are only stored in memory.
    ///   - creatorName: The name of the application creating the HAR file.
    ///   - creatorVersion: The version of the application.
    public init(
        filePath: AbsolutePath? = nil,
        creatorName: String = "Tuist",
        creatorVersion: String = Constants.version
    ) {
        self.filePath = filePath
        log = HAR.Log(
            creator: HAR.Creator(name: creatorName, version: creatorVersion)
        )
    }

    /// Records a new entry to the HAR log.
    /// - Parameter entry: The entry to record.
    public func record(_ entry: HAR.Entry) async {
        log.entries.append(entry)
        await persist()
    }

    /// Records an HTTP request and response.
    public func recordRequest(
        url: URL,
        method: String,
        requestHeaders: [HAR.Header],
        requestBody: Data?,
        responseStatusCode: Int,
        responseStatusText: String,
        responseHeaders: [HAR.Header],
        responseBody: Data?,
        startTime: Date,
        endTime: Date,
        timings: HAR.Timings? = nil,
        httpVersion: String? = nil,
        requestHeadersSize: Int? = nil,
        responseHeadersSize: Int? = nil,
        requestBodySize: Int? = nil
    ) async {
        let entry = buildEntry(
            url: url,
            method: method,
            requestHeaders: requestHeaders,
            requestBody: requestBody,
            responseStatusCode: responseStatusCode,
            responseStatusText: responseStatusText,
            responseHeaders: responseHeaders,
            responseBody: responseBody,
            startTime: startTime,
            endTime: endTime,
            timings: timings,
            httpVersion: httpVersion,
            requestHeadersSize: requestHeadersSize,
            responseHeadersSize: responseHeadersSize,
            requestBodySize: requestBodySize
        )
        await record(entry)
    }

    /// Records an HTTP request and response from URLRequest/HTTPURLResponse.
    public func recordRequest(
        request: URLRequest,
        response: HTTPURLResponse,
        requestBody: Data?,
        responseBody: Data?,
        startTime: Date,
        endTime: Date,
        timings: HAR.Timings? = nil,
        httpVersion: String? = nil,
        requestHeadersSize: Int? = nil,
        responseHeadersSize: Int? = nil,
        requestBodySize: Int? = nil
    ) async {
        guard let url = request.url else { return }
        await recordRequest(
            url: url,
            method: request.httpMethod ?? "GET",
            requestHeaders: Self.headers(from: request),
            requestBody: requestBody,
            responseStatusCode: response.statusCode,
            responseStatusText: HTTPURLResponse.localizedString(forStatusCode: response.statusCode),
            responseHeaders: Self.headers(from: response),
            responseBody: responseBody,
            startTime: startTime,
            endTime: endTime,
            timings: timings,
            httpVersion: httpVersion,
            requestHeadersSize: requestHeadersSize,
            responseHeadersSize: responseHeadersSize,
            requestBodySize: requestBodySize
        )
    }

    /// Records a failed HTTP request.
    public func recordError(
        url: URL,
        method: String,
        requestHeaders: [HAR.Header],
        requestBody: Data?,
        error: Error,
        startTime: Date,
        endTime: Date,
        timings: HAR.Timings? = nil,
        httpVersion: String? = nil,
        requestHeadersSize: Int? = nil,
        requestBodySize: Int? = nil
    ) async {
        let entry = buildErrorEntry(
            url: url,
            method: method,
            requestHeaders: requestHeaders,
            requestBody: requestBody,
            error: error,
            startTime: startTime,
            endTime: endTime,
            timings: timings,
            httpVersion: httpVersion,
            requestHeadersSize: requestHeadersSize,
            requestBodySize: requestBodySize
        )
        await record(entry)
    }

    /// Records a failed HTTP request from URLRequest.
    public func recordError(
        request: URLRequest,
        error: Error,
        requestBody: Data?,
        startTime: Date,
        endTime: Date,
        timings: HAR.Timings? = nil,
        httpVersion: String? = nil,
        requestHeadersSize: Int? = nil,
        requestBodySize: Int? = nil
    ) async {
        guard let url = request.url else { return }
        await recordError(
            url: url,
            method: request.httpMethod ?? "GET",
            requestHeaders: Self.headers(from: request),
            requestBody: requestBody,
            error: error,
            startTime: startTime,
            endTime: endTime,
            timings: timings,
            httpVersion: httpVersion,
            requestHeadersSize: requestHeadersSize,
            requestBodySize: requestBodySize
        )
    }

    /// Returns the current HAR log.
    public func getLog() async -> HAR.Log {
        log
    }

    /// Returns all recorded entries.
    public func getEntries() async -> [HAR.Entry] {
        log.entries
    }

    /// Filters sensitive headers from a list of headers.
    /// - Parameter headers: The headers to filter.
    /// - Returns: Headers with sensitive values redacted.
    public static func filterSensitiveHeaders(_ headers: [HAR.Header]) -> [HAR.Header] {
        headers.map { header in
            if sensitiveHeaders.contains(header.name.lowercased()) {
                return HAR.Header(name: header.name, value: "[REDACTED]", comment: header.comment)
            }
            return header
        }
    }

    /// Persists the current HAR log to disk if a file path was provided.
    private func persist() async {
        guard let filePath else { return }
        do {
            let data = try HAR.encode(log)
            try data.write(to: filePath.url, options: .atomic)
        } catch {
            Logger.current.debug("Failed to persist HAR file: \(error)")
        }
    }

}

// MARK: - Entry Building

extension HARRecorder {
    private func buildEntry(
        url: URL,
        method: String,
        requestHeaders: [HAR.Header],
        requestBody: Data?,
        responseStatusCode: Int,
        responseStatusText: String,
        responseHeaders: [HAR.Header],
        responseBody: Data?,
        startTime: Date,
        endTime: Date,
        timings: HAR.Timings? = nil,
        httpVersion: String? = nil,
        requestHeadersSize: Int? = nil,
        responseHeadersSize: Int? = nil,
        requestBodySize: Int? = nil
    ) -> HAR.Entry {
        let durationMs = Int((endTime.timeIntervalSince(startTime)) * 1000)
        let filteredRequestHeaders = Self.filterSensitiveHeaders(requestHeaders)
        let filteredResponseHeaders = Self.filterSensitiveHeaders(responseHeaders)

        let entryTimings = timings ?? HAR.Timings(
            send: 0,
            wait: durationMs,
            receive: 0
        )

        let resolvedHttpVersion = Self.formatHttpVersion(httpVersion)
        let resolvedRequestHeadersSize = Self.resolveRequestHeadersSize(
            requestHeadersSize,
            method: method,
            url: url,
            httpVersion: resolvedHttpVersion,
            headers: requestHeaders
        )
        let resolvedResponseHeadersSize = Self.resolveResponseHeadersSize(
            responseHeadersSize,
            httpVersion: resolvedHttpVersion,
            statusCode: responseStatusCode,
            statusText: responseStatusText,
            headers: responseHeaders
        )

        return HAR.Entry(
            startedDateTime: startTime,
            time: durationMs,
            request: HAR.Request(
                method: method,
                url: url.absoluteString,
                httpVersion: resolvedHttpVersion,
                cookies: [],
                headers: filteredRequestHeaders,
                queryString: extractQueryParameters(from: url),
                postData: buildPostData(from: requestBody, headers: requestHeaders),
                headersSize: resolvedRequestHeadersSize,
                bodySize: requestBodySize ?? requestBody?.count ?? 0
            ),
            response: HAR.Response(
                status: responseStatusCode,
                statusText: responseStatusText,
                httpVersion: resolvedHttpVersion,
                cookies: [],
                headers: filteredResponseHeaders,
                content: buildContent(from: responseBody, headers: responseHeaders),
                redirectURL: "",
                headersSize: resolvedResponseHeadersSize,
                bodySize: responseBody?.count ?? 0
            ),
            timings: entryTimings
        )
    }

    private func buildErrorEntry(
        url: URL,
        method: String,
        requestHeaders: [HAR.Header],
        requestBody: Data?,
        error: Error,
        startTime: Date,
        endTime: Date,
        timings: HAR.Timings? = nil,
        httpVersion: String? = nil,
        requestHeadersSize: Int? = nil,
        requestBodySize: Int? = nil
    ) -> HAR.Entry {
        let durationMs = Int((endTime.timeIntervalSince(startTime)) * 1000)
        let filteredRequestHeaders = Self.filterSensitiveHeaders(requestHeaders)
        let errorMessage = String(describing: error)

        let entryTimings = timings ?? HAR.Timings(
            send: 0,
            wait: durationMs,
            receive: 0
        )

        let resolvedHttpVersion = Self.formatHttpVersion(httpVersion)
        let resolvedRequestHeadersSize = Self.resolveRequestHeadersSize(
            requestHeadersSize,
            method: method,
            url: url,
            httpVersion: resolvedHttpVersion,
            headers: requestHeaders
        )

        return HAR.Entry(
            startedDateTime: startTime,
            time: durationMs,
            request: HAR.Request(
                method: method,
                url: url.absoluteString,
                httpVersion: resolvedHttpVersion,
                cookies: [],
                headers: filteredRequestHeaders,
                queryString: extractQueryParameters(from: url),
                postData: buildPostData(from: requestBody, headers: requestHeaders),
                headersSize: resolvedRequestHeadersSize,
                bodySize: requestBodySize ?? requestBody?.count ?? 0
            ),
            response: HAR.Response(
                status: 0,
                statusText: "Error",
                httpVersion: resolvedHttpVersion,
                cookies: [],
                headers: [],
                content: HAR.Content(
                    size: errorMessage.utf8.count,
                    mimeType: "text/plain",
                    text: errorMessage
                ),
                redirectURL: "",
                headersSize: -1,
                bodySize: errorMessage.utf8.count
            ),
            timings: entryTimings
        )
    }

    private func extractQueryParameters(from url: URL) -> [HAR.QueryParameter] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let queryItems = components.queryItems
        else {
            return []
        }
        return queryItems.map { HAR.QueryParameter(name: $0.name, value: $0.value ?? "") }
    }

    private func buildPostData(from data: Data?, headers: [HAR.Header]) -> HAR.PostData? {
        guard let data, !data.isEmpty else { return nil }

        let mimeType = headers.first { $0.name.lowercased() == "content-type" }?.value ?? "application/octet-stream"

        if let text = String(data: data, encoding: .utf8) {
            return HAR.PostData(mimeType: mimeType, text: text)
        } else {
            return HAR.PostData(mimeType: mimeType, text: data.base64EncodedString())
        }
    }

    private func buildContent(from data: Data?, headers: [HAR.Header]) -> HAR.Content {
        let mimeType = headers.first { $0.name.lowercased() == "content-type" }?.value ?? "application/octet-stream"

        guard let data, !data.isEmpty else {
            return HAR.Content(size: 0, mimeType: mimeType)
        }

        if let text = String(data: data, encoding: .utf8) {
            return HAR.Content(size: data.count, mimeType: mimeType, text: text)
        } else {
            return HAR.Content(
                size: data.count,
                mimeType: mimeType,
                text: data.base64EncodedString(),
                encoding: "base64"
            )
        }
    }
}

// MARK: - Static Helpers

extension HARRecorder {
    static func headers(from request: URLRequest) -> [HAR.Header] {
        (request.allHTTPHeaderFields ?? [:]).map { HAR.Header(name: $0.key, value: $0.value) }
    }

    static func headers(from response: HTTPURLResponse) -> [HAR.Header] {
        (response.allHeaderFields as? [String: String] ?? [:]).map { HAR.Header(name: $0.key, value: $0.value) }
    }

    private static func calculateHeadersSize(startLine: String, headers: [HAR.Header]) -> Int {
        var size = startLine.utf8.count + 2
        for header in headers {
            size += header.name.utf8.count + 2 + header.value.utf8.count + 2
        }
        size += 2
        return size
    }

    private static func requestTarget(for url: URL) -> String {
        var target = url.path.isEmpty ? "/" : url.path
        if let query = url.query, !query.isEmpty {
            target += "?\(query)"
        }
        return target
    }

    private static func formatHttpVersion(_ protocolName: String?) -> String {
        guard let protocolName else { return "HTTP/1.1" }
        switch protocolName.lowercased() {
        case "h2", "http/2", "http/2.0":
            return "HTTP/2"
        case "h3", "http/3", "http/3.0":
            return "HTTP/3"
        case "http/1.1":
            return "HTTP/1.1"
        case "http/1.0":
            return "HTTP/1.0"
        default:
            return protocolName.uppercased()
        }
    }

    private static func resolveRequestHeadersSize(
        _ provided: Int?,
        method: String,
        url: URL,
        httpVersion: String,
        headers: [HAR.Header]
    ) -> Int {
        if let provided { return provided }
        let requestLine = "\(method) \(requestTarget(for: url)) \(httpVersion)"
        return calculateHeadersSize(startLine: requestLine, headers: headers)
    }

    private static func resolveResponseHeadersSize(
        _ provided: Int?,
        httpVersion: String,
        statusCode: Int,
        statusText: String,
        headers: [HAR.Header]
    ) -> Int {
        if let provided { return provided }
        let statusLine = statusText.isEmpty
            ? "\(httpVersion) \(statusCode)"
            : "\(httpVersion) \(statusCode) \(statusText)"
        return calculateHeadersSize(startLine: statusLine, headers: headers)
    }
}
