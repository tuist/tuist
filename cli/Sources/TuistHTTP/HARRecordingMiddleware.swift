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

            let fallbackStartTime = Date()
            let (requestBodyData, requestBodyForNext) = try await collectBody(body)

            let fullURL = buildURL(baseURL: baseURL, path: request.path)
            let method = request.method.rawValue
            let requestHeaders = request.headerFields.map { HAR.Header(name: $0.name.rawName, value: $0.value) }

            do {
                let (response, responseBody) = try await next(request, requestBodyForNext, baseURL)

                let fallbackEndTime = Date()
                let (responseBodyData, responseBodyForNext) = try await collectBody(responseBody)

                let (timings, actualStartTime, actualEndTime) = retrieveTimingsAndDates(for: fullURL, fallbackStart: fallbackStartTime, fallbackEnd: fallbackEndTime)
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
                        startTime: actualStartTime,
                        endTime: actualEndTime,
                        timings: timings
                    )
                }

                return (response, responseBodyForNext)
            } catch {
                let fallbackEndTime = Date()
                let (timings, actualStartTime, actualEndTime) = retrieveTimingsAndDates(for: fullURL, fallbackStart: fallbackStartTime, fallbackEnd: fallbackEndTime)

                Task.detached {
                    await recorder.recordError(
                        url: fullURL,
                        method: method,
                        requestHeaders: requestHeaders,
                        requestBody: requestBodyData,
                        error: error,
                        startTime: actualStartTime,
                        endTime: actualEndTime,
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
        private func collectBody(_ body: HTTPBody?) async throws -> (Data?, HTTPBody?) {
            switch body?.length {
            case .none, .unknown:
                return (nil, body)
            case let .known(length):
                let bodyData = try await Data(collecting: body!, upTo: Int(length))
                return (bodyData, HTTPBody(bodyData))
            }
        }

        private func retrieveTimingsAndDates(for url: URL, fallbackStart: Date, fallbackEnd: Date) -> (HAR.Timings?, Date, Date) {
            guard let metrics = URLSessionMetricsDelegate.shared.retrieveMetrics(for: url) else {
                return (nil, fallbackStart, fallbackEnd)
            }
            let timings = URLSessionMetricsDelegate.convertToHARTimings(metrics)
            let startTime = metrics.fetchStartDate ?? fallbackStart
            let endTime = metrics.responseEndDate ?? fallbackEnd
            return (timings, startTime, endTime)
        }

        private func buildURL(baseURL: URL, path: String?) -> URL {
            guard let path, !path.isEmpty else {
                return baseURL
            }

            guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: true) else {
                return baseURL
            }

            let pathAndQuery = path.split(separator: "?", maxSplits: 1)
            let pathPart = String(pathAndQuery[0])
            components.path = pathPart.hasPrefix("/") ? pathPart : "/" + pathPart

            if pathAndQuery.count > 1 {
                components.query = String(pathAndQuery[1])
            }

            return components.url ?? baseURL
        }
    #endif
}
