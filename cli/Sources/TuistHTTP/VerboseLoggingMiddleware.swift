import Foundation
import HTTPTypes
import OpenAPIRuntime

#if os(macOS)
    import TuistSupport
#endif

/// A middleware that outputs in debug mode the request and responses sent and received from the server
public struct VerboseLoggingMiddleware: ClientMiddleware {
    private let serviceName: String

    public init(serviceName: String = "Tuist") {
        self.serviceName = serviceName
    }

    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID _: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let (requestBodyToLog, requestBodyForNext) = try await process(body)
        #if os(macOS)
            Logger.current.debug("""
            Sending HTTP request to \(serviceName):
              - Method: \(request.method.rawValue)
              - URL: \(baseURL.absoluteString)
              - Path: \(request.path ?? "")
              - Body: \(requestBodyToLog)
              - Headers: \(request.headerFields)
            """)
        #endif

        let (response, responseBody) = try await next(request, requestBodyForNext, baseURL)
        let (responseBodyToLog, responseBodyForNext) = try await process(responseBody)

        #if os(macOS)
            Logger.current.debug("""
            Received HTTP response from \(serviceName):
              - URL: \(baseURL.absoluteString)
              - Path: \(request.path ?? "")
              - Status: \(response.status.code)
              - Body: \(responseBodyToLog)
              - Headers: \(response.headerFields)
            """)
        #endif

        return (response, responseBodyForNext)
    }

    public enum BodyLog: Equatable, CustomStringConvertible {
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

        public var description: String {
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

    public func process(_ body: HTTPBody?) async throws -> (bodyToLog: BodyLog, bodyForNext: HTTPBody?) {
        switch body?.length {
        case .none: return (.none, body)
        case .unknown: return (.unknownLength, body)
        case let .known(length):
            let bodyData = try await Data(collecting: body!, upTo: Int(length))
            return (.complete(bodyData), HTTPBody(bodyData))
        }
    }
}
