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
            let (requestBodyData, requestBodyForNext) = try await collectBody(body)

            let entryBuilder = HAREntryBuilder()

            let fullURL = entryBuilder.buildURL(baseURL: baseURL, path: request.path)

            do {
                let (response, responseBody) = try await next(request, requestBodyForNext, baseURL)

                let endTime = Date()
                let (responseBodyData, responseBodyForNext) = try await collectBody(responseBody)

                let timings = retrieveTimings(for: fullURL)

                let entry = entryBuilder.buildEntry(
                    url: fullURL,
                    method: request.method.rawValue,
                    requestHeaders: request.headerFields.map { HAR.Header(name: $0.name.rawName, value: $0.value) },
                    requestBody: requestBodyData,
                    responseStatusCode: response.status.code,
                    responseStatusText: response.status.reasonPhrase ?? "",
                    responseHeaders: response.headerFields.map { HAR.Header(name: $0.name.rawName, value: $0.value) },
                    responseBody: responseBodyData,
                    startTime: startTime,
                    endTime: endTime,
                    timings: timings
                )

                await recorder.record(entry)

                return (response, responseBodyForNext)
            } catch {
                let endTime = Date()
                let timings = retrieveTimings(for: fullURL)

                let entry = entryBuilder.buildErrorEntry(
                    url: fullURL,
                    method: request.method.rawValue,
                    requestHeaders: request.headerFields.map { HAR.Header(name: $0.name.rawName, value: $0.value) },
                    requestBody: requestBodyData,
                    error: error,
                    startTime: startTime,
                    endTime: endTime,
                    timings: timings
                )

                await recorder.record(entry)

                throw error
            }
        #else
            return try await next(request, body, baseURL)
        #endif
    }

    #if os(macOS)
        private func collectBody(_ body: HTTPBody?) async throws -> (Data?, HTTPBody?) {
            switch body?.length {
            case .none, .unknown:
                return (nil, body)
            case let .known(length):
                let bodyData = try await Data(collecting: body!, upTo: Int(length))
                return (bodyData, HTTPBody(bodyData))
            }
        }

        private func retrieveTimings(for url: URL) -> HAR.Timings? {
            guard let metrics = URLSessionMetricsDelegate.shared.retrieveMetrics(for: url) else {
                return nil
            }
            return URLSessionMetricsDelegate.convertToHARTimings(metrics)
        }
    #endif
}
