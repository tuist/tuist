import Foundation
import HTTPTypes
import OpenAPIRuntime
import ServiceContextModule

/// A middleware that outputs in debug mode the request and responses sent and received from the server
struct ServerClientVerboseLoggingMiddleware: ClientMiddleware {
    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID _: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let (requestBodyToLog, requestBodyForNext) = try await process(body)
        #if canImport(TuistSupport)
            ServiceContext.current?.logger?.debug("""
            Sending HTTP request to Tuist:
              - Method: \(request.method.rawValue)
              - URL: \(baseURL.absoluteString)
              - Path: \(request.path ?? "")
              - Body: \(requestBodyToLog)
              - Headers: \(request.headerFields)
            """)
        #endif

        let (response, responseBody) = try await next(request, requestBodyForNext, baseURL)
        let (responseBodyToLog, responseBodyForNext) = try await process(responseBody)

        #if canImport(TuistSupport)
            ServiceContext.current?.logger?.debug("""
            Received HTTP response from Tuist:
              - URL: \(baseURL.absoluteString)
              - Path: \(request.path ?? "")
              - Status: \(response.status.code)
              - Body: \(responseBodyToLog)
              - Headers: \(response.headerFields)
            """)
        #endif

        return (response, responseBodyForNext)
    }

    enum BodyLog: Equatable, CustomStringConvertible {
        /// There is no body to log.
        case none
        /// The policy forbids logging the body.
        case redacted
        /// The body was of unknown length.
        case unknownLength
        /// The body exceeds the maximum size for logging allowed by the policy.
        case tooManyBytesToLog(Int64)
        /// The body can be logged.
        case complete(Data)

        var description: String {
            switch self {
            case .none: return "<none>"
            case .redacted: return "<redacted>"
            case .unknownLength: return "<unknown length>"
            case let .tooManyBytesToLog(byteCount): return "<\(byteCount) bytes>"
            case let .complete(data):
                if let string = String(data: data, encoding: .utf8) { return string }
                return String(describing: data)
            }
        }
    }

    func process(_ body: HTTPBody?) async throws -> (bodyToLog: BodyLog, bodyForNext: HTTPBody?) {
        switch body?.length {
        case .none: return (.none, body)
        case .unknown: return (.unknownLength, body)
        case let .known(length):
            let bodyData = try await Data(collecting: body!, upTo: Int(length))
            return (.complete(bodyData), HTTPBody(bodyData))
        }
    }
}
