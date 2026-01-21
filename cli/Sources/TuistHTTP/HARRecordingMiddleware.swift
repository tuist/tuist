import Foundation
import HTTPTypes
import OpenAPIRuntime

#if os(macOS)
    import TuistSupport
#endif

/// A middleware that records HTTP requests and responses to a HAR file.
public struct HARRecordingMiddleware: ClientMiddleware {
    public init() {}

    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID _: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        #if os(macOS)
            guard let recorder = HARRecorder.current else {
                return try await next(request, body, baseURL)
            }

            let startTime = Date()
            let (requestBodyData, requestBodyForNext) = try await processBody(body)

            do {
                let (response, responseBody) = try await next(request, requestBodyForNext, baseURL)

                let endTime = Date()
                let (responseBodyData, responseBodyForNext) = try await processBody(responseBody)

                let entry = createEntry(
                    request: request,
                    requestBody: requestBodyData,
                    response: response,
                    responseBody: responseBodyData,
                    baseURL: baseURL,
                    startTime: startTime,
                    endTime: endTime
                )

                await recorder.record(entry)

                return (response, responseBodyForNext)
            } catch {
                let endTime = Date()
                let entry = createErrorEntry(
                    request: request,
                    requestBody: requestBodyData,
                    error: error,
                    baseURL: baseURL,
                    startTime: startTime,
                    endTime: endTime
                )

                await recorder.record(entry)

                throw error
            }
        #else
            return try await next(request, body, baseURL)
        #endif
    }

    #if os(macOS)
        private func processBody(_ body: HTTPBody?) async throws -> (Data?, HTTPBody?) {
            switch body?.length {
            case .none:
                return (nil, body)
            case .unknown:
                return (nil, body)
            case let .known(length):
                let bodyData = try await Data(collecting: body!, upTo: Int(length))
                return (bodyData, HTTPBody(bodyData))
            }
        }

        private func createEntry(
            request: HTTPRequest,
            requestBody: Data?,
            response: HTTPResponse,
            responseBody: Data?,
            baseURL: URL,
            startTime: Date,
            endTime: Date
        ) -> HAR.Entry {
            let durationMs = Int((endTime.timeIntervalSince(startTime)) * 1000)

            let fullURL = constructFullURL(baseURL: baseURL, request: request)
            let queryParameters = extractQueryParameters(from: fullURL)

            let requestHeaders = HARRecorder.filterSensitiveHeaders(
                request.headerFields.map { HAR.Header(name: $0.name.rawName, value: $0.value) }
            )

            let responseHeaders = HARRecorder.filterSensitiveHeaders(
                response.headerFields.map { HAR.Header(name: $0.name.rawName, value: $0.value) }
            )

            let postData = createPostData(from: requestBody, headers: request.headerFields)
            let content = createContent(from: responseBody, headers: response.headerFields)

            return HAR.Entry(
                startedDateTime: startTime,
                time: durationMs,
                request: HAR.Request(
                    method: request.method.rawValue,
                    url: fullURL,
                    httpVersion: "HTTP/1.1",
                    cookies: [],
                    headers: requestHeaders,
                    queryString: queryParameters,
                    postData: postData,
                    headersSize: -1,
                    bodySize: requestBody?.count ?? 0
                ),
                response: HAR.Response(
                    status: response.status.code,
                    statusText: response.status.reasonPhrase ?? "",
                    httpVersion: "HTTP/1.1",
                    cookies: [],
                    headers: responseHeaders,
                    content: content,
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

        private func constructFullURL(baseURL: URL, request: HTTPRequest) -> String {
            guard let path = request.path else {
                return baseURL.absoluteString
            }
            var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true)
            if path.hasPrefix("/") {
                components?.path = path.split(separator: "?").first.map(String.init) ?? path
                if let queryStart = path.firstIndex(of: "?") {
                    components?.query = String(path[path.index(after: queryStart)...])
                }
            } else {
                components?.path = "/" + (path.split(separator: "?").first.map(String.init) ?? path)
                if let queryStart = path.firstIndex(of: "?") {
                    components?.query = String(path[path.index(after: queryStart)...])
                }
            }
            return components?.url?.absoluteString ?? baseURL.absoluteString + path
        }

        private func extractQueryParameters(from urlString: String) -> [HAR.QueryParameter] {
            guard let url = URL(string: urlString),
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
                  let queryItems = components.queryItems
            else {
                return []
            }
            return queryItems.map { HAR.QueryParameter(name: $0.name, value: $0.value ?? "") }
        }

        private func createPostData(from data: Data?, headers: HTTPFields) -> HAR.PostData? {
            guard let data, !data.isEmpty else { return nil }

            let mimeType = headers.first { $0.name == .contentType }?.value ?? "application/octet-stream"

            if let text = String(data: data, encoding: .utf8) {
                return HAR.PostData(mimeType: mimeType, text: text)
            } else {
                return HAR.PostData(mimeType: mimeType, text: data.base64EncodedString())
            }
        }

        private func createContent(from data: Data?, headers: HTTPFields) -> HAR.Content {
            let mimeType = headers.first { $0.name == .contentType }?.value ?? "application/octet-stream"

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

        private func createErrorEntry(
            request: HTTPRequest,
            requestBody: Data?,
            error: Error,
            baseURL: URL,
            startTime: Date,
            endTime: Date
        ) -> HAR.Entry {
            let durationMs = Int((endTime.timeIntervalSince(startTime)) * 1000)

            let fullURL = constructFullURL(baseURL: baseURL, request: request)
            let queryParameters = extractQueryParameters(from: fullURL)

            let requestHeaders = HARRecorder.filterSensitiveHeaders(
                request.headerFields.map { HAR.Header(name: $0.name.rawName, value: $0.value) }
            )

            let postData = createPostData(from: requestBody, headers: request.headerFields)

            let errorMessage = String(describing: error)
            let errorContent = HAR.Content(
                size: errorMessage.utf8.count,
                mimeType: "text/plain",
                text: errorMessage
            )

            return HAR.Entry(
                startedDateTime: startTime,
                time: durationMs,
                request: HAR.Request(
                    method: request.method.rawValue,
                    url: fullURL,
                    httpVersion: "HTTP/1.1",
                    cookies: [],
                    headers: requestHeaders,
                    queryString: queryParameters,
                    postData: postData,
                    headersSize: -1,
                    bodySize: requestBody?.count ?? 0
                ),
                response: HAR.Response(
                    status: 0,
                    statusText: "Error",
                    httpVersion: "HTTP/1.1",
                    cookies: [],
                    headers: [],
                    content: errorContent,
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
    #endif
}
