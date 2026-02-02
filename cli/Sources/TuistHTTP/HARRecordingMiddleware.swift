import Foundation
import HTTPTypes
import OpenAPIRuntime

#if canImport(TuistHAR)
    import TuistHAR

    public typealias HARRecordingMiddleware = TuistHAR.HARRecordingMiddleware
#else
    public struct HARRecordingMiddleware: ClientMiddleware {
        public init() {}

        public func intercept(
            _ request: HTTPRequest,
            body: HTTPBody?,
            baseURL: URL,
            operationID _: String,
            next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
        ) async throws -> (HTTPResponse, HTTPBody?) {
            try await next(request, body, baseURL)
        }
    }
#endif
