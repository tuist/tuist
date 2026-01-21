import Foundation

/// Builds HAR entries from HTTP request and response data.
public struct HAREntryBuilder {
    public init() {}

    /// Creates a HAR entry from request and response data.
    public func buildEntry(
        url: URL,
        method: String,
        requestHeaders: [HAR.Header],
        requestBody: Data?,
        responseStatusCode: Int,
        responseStatusText: String,
        responseHeaders: [HAR.Header],
        responseBody: Data?,
        startTime: Date,
        endTime: Date
    ) -> HAR.Entry {
        let durationMs = Int((endTime.timeIntervalSince(startTime)) * 1000)
        let filteredRequestHeaders = HARRecorder.filterSensitiveHeaders(requestHeaders)
        let filteredResponseHeaders = HARRecorder.filterSensitiveHeaders(responseHeaders)

        return HAR.Entry(
            startedDateTime: startTime,
            time: durationMs,
            request: HAR.Request(
                method: method,
                url: url.absoluteString,
                httpVersion: "HTTP/1.1",
                cookies: [],
                headers: filteredRequestHeaders,
                queryString: extractQueryParameters(from: url),
                postData: buildPostData(from: requestBody, headers: requestHeaders),
                headersSize: -1,
                bodySize: requestBody?.count ?? 0
            ),
            response: HAR.Response(
                status: responseStatusCode,
                statusText: responseStatusText,
                httpVersion: "HTTP/1.1",
                cookies: [],
                headers: filteredResponseHeaders,
                content: buildContent(from: responseBody, headers: responseHeaders),
                redirectURL: "",
                headersSize: -1,
                bodySize: responseBody?.count ?? 0
            ),
            timings: HAR.Timings(
                send: 0,
                wait: durationMs,
                receive: 0
            )
        )
    }

    /// Creates a HAR entry for a failed request.
    public func buildErrorEntry(
        url: URL,
        method: String,
        requestHeaders: [HAR.Header],
        requestBody: Data?,
        error: Error,
        startTime: Date,
        endTime: Date
    ) -> HAR.Entry {
        let durationMs = Int((endTime.timeIntervalSince(startTime)) * 1000)
        let filteredRequestHeaders = HARRecorder.filterSensitiveHeaders(requestHeaders)
        let errorMessage = String(describing: error)

        return HAR.Entry(
            startedDateTime: startTime,
            time: durationMs,
            request: HAR.Request(
                method: method,
                url: url.absoluteString,
                httpVersion: "HTTP/1.1",
                cookies: [],
                headers: filteredRequestHeaders,
                queryString: extractQueryParameters(from: url),
                postData: buildPostData(from: requestBody, headers: requestHeaders),
                headersSize: -1,
                bodySize: requestBody?.count ?? 0
            ),
            response: HAR.Response(
                status: 0,
                statusText: "Error",
                httpVersion: "HTTP/1.1",
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
            timings: HAR.Timings(
                send: 0,
                wait: durationMs,
                receive: 0
            )
        )
    }

    /// Extracts query parameters from a URL.
    public func extractQueryParameters(from url: URL) -> [HAR.QueryParameter] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let queryItems = components.queryItems
        else {
            return []
        }
        return queryItems.map { HAR.QueryParameter(name: $0.name, value: $0.value ?? "") }
    }

    /// Builds a full URL from a base URL and a path.
    public func buildURL(baseURL: URL, path: String?) -> URL {
        guard let path, !path.isEmpty else {
            return baseURL
        }
        return baseURL.appendingPathComponent(path.hasPrefix("/") ? String(path.dropFirst()) : path)
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
