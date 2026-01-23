import Foundation
import HTTPTypes
import OpenAPIRuntime

#if canImport(TuistHAR)
    import TuistHAR
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
        #if canImport(TuistHAR)
            guard let recorder = HARRecorder.current else {
                return try await next(request, body, baseURL)
            }

            let requestContentType = request.headerFields[.contentType]
            let (requestBodyData, requestBodyForNext) = try await collectBody(body, contentType: requestContentType)

            let fullURL = buildURL(baseURL: baseURL, path: request.path)
            let method = request.method.rawValue
            let requestHeaders = request.headerFields.map { HAR.Header(name: $0.name.rawName, value: $0.value) }

            do {
                let (response, responseBody) = try await next(request, requestBodyForNext, baseURL)

                let responseContentType = response.headerFields[.contentType]
                let (responseBodyData, responseBodyForNext) = try await collectBody(
                    responseBody,
                    contentType: responseContentType
                )

                let (timings, startTime, endTime) = retrieveTimingsAndDates(for: fullURL)
                let statusCode = response.status.code
                let statusText = response.status.reasonPhrase ?? ""
                let responseHeaders = response.headerFields.map { HAR.Header(name: $0.name.rawName, value: $0.value) }

                Task.detached {
                    await recorder.recordRequest(
                        url: fullURL,
                        method: method,
                        requestHeaders: requestHeaders,
                        requestBody: requestBodyData,
                        responseStatusCode: statusCode,
                        responseStatusText: statusText,
                        responseHeaders: responseHeaders,
                        responseBody: responseBodyData,
                        startTime: startTime,
                        endTime: endTime,
                        timings: timings
                    )
                }

                return (response, responseBodyForNext)
            } catch {
                let (timings, startTime, endTime) = retrieveTimingsAndDates(for: fullURL)

                Task.detached {
                    await recorder.recordError(
                        url: fullURL,
                        method: method,
                        requestHeaders: requestHeaders,
                        requestBody: requestBodyData,
                        error: error,
                        startTime: startTime,
                        endTime: endTime,
                        timings: timings
                    )
                }

                throw error
            }
        #else
            return try await next(request, body, baseURL)
        #endif
    }

    #if canImport(TuistHAR)
        private static let maxBodySizeForRecording: Int64 = 1024 * 1024 // 1 MB

        private func collectBody(_ body: HTTPBody?, contentType: String? = nil) async throws -> (Data?, HTTPBody?) {
            switch body?.length {
            case .none, .unknown:
                return (nil, body)
            case let .known(length):
                if length > Self.maxBodySizeForRecording || isBinaryContentType(contentType) {
                    return (nil, body)
                }
                let bodyData = try await Data(collecting: body!, upTo: Int(length))
                return (bodyData, HTTPBody(bodyData))
            }
        }

        private func isBinaryContentType(_ contentType: String?) -> Bool {
            guard let contentType = contentType?.lowercased() else { return false }
            let binaryTypes = [
                "application/octet-stream",
                "application/zip",
                "application/x-tar",
                "application/gzip",
                "application/x-gzip",
                "image/",
                "video/",
                "audio/",
            ]
            return binaryTypes.contains { contentType.hasPrefix($0) }
        }

        private func retrieveTimingsAndDates(for url: URL) -> (HAR.Timings?, Date, Date) {
            guard let metrics = URLSessionMetricsDelegate.shared.retrieveMetrics(for: url),
                  let startTime = metrics.fetchStartDate,
                  let endTime = metrics.responseEndDate
            else {
                let now = Date()
                return (nil, now, now)
            }
            let timings = URLSessionMetricsDelegate.convertToHARTimings(metrics)
            return (timings, startTime, endTime)
        }

        private func buildURL(baseURL: URL, path: String?) -> URL {
            guard let path, !path.isEmpty else {
                return baseURL
            }

            guard var baseComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: true) else {
                return baseURL
            }

            guard let pathComponents = URLComponents(string: path) else {
                baseComponents.path = path.hasPrefix("/") ? path : "/" + path
                return baseComponents.url ?? baseURL
            }

            if !pathComponents.path.isEmpty {
                let newPath = pathComponents.path
                baseComponents.path = newPath.hasPrefix("/") ? newPath : "/" + newPath
            }

            if let queryItems = pathComponents.queryItems, !queryItems.isEmpty {
                baseComponents.queryItems = queryItems
            }

            return baseComponents.url ?? baseURL
        }
    #endif
}
