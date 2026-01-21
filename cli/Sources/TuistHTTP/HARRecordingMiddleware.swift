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

            do {
                let (response, responseBody) = try await next(request, requestBodyForNext, baseURL)

                let endTime = Date()
                let (responseBodyData, responseBodyForNext) = try await collectBody(responseBody)

                let entry = HAREntryBuilder().buildEntry(
                    url: buildFullURL(baseURL: baseURL, path: request.path),
                    method: request.method.rawValue,
                    requestHeaders: request.headerFields.map { HAR.Header(name: $0.name.rawName, value: $0.value) },
                    requestBody: requestBodyData,
                    responseStatusCode: response.status.code,
                    responseStatusText: response.status.reasonPhrase ?? "",
                    responseHeaders: response.headerFields.map { HAR.Header(name: $0.name.rawName, value: $0.value) },
                    responseBody: responseBodyData,
                    startTime: startTime,
                    endTime: endTime
                )

                await recorder.record(entry)

                return (response, responseBodyForNext)
            } catch {
                let endTime = Date()
                let entry = HAREntryBuilder().buildErrorEntry(
                    url: buildFullURL(baseURL: baseURL, path: request.path),
                    method: request.method.rawValue,
                    requestHeaders: request.headerFields.map { HAR.Header(name: $0.name.rawName, value: $0.value) },
                    requestBody: requestBodyData,
                    error: error,
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
        private func collectBody(_ body: HTTPBody?) async throws -> (Data?, HTTPBody?) {
            switch body?.length {
            case .none, .unknown:
                return (nil, body)
            case let .known(length):
                let bodyData = try await Data(collecting: body!, upTo: Int(length))
                return (bodyData, HTTPBody(bodyData))
            }
        }

        private func buildFullURL(baseURL: URL, path: String?) -> URL {
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
