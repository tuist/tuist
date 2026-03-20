import Foundation
import HTTPTypes
import OpenAPIRuntime

import TuistLogging

/// A middleware that outputs in debug mode the request and responses sent and received from the server
public struct VerboseLoggingMiddleware: ClientMiddleware {
    private let serviceName: String

    private static let sensitiveHeaders: Set<String> = [
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
        Logger.current.debug("""
        Sending HTTP request to \(serviceName):
          - Method: \(request.method.rawValue)
          - URL: \(baseURL.absoluteString)
          - Path: \(request.path ?? "")
          - Body: \(requestBodyToLog)
          - Headers: \(Self.redactSensitiveHeaders(request.headerFields))
        """)

        let (response, responseBody) = try await next(request, requestBodyForNext, baseURL)
        let (responseBodyToLog, responseBodyForNext) = try await process(responseBody)

        Logger.current.debug("""
        Received HTTP response from \(serviceName):
          - URL: \(baseURL.absoluteString)
          - Path: \(request.path ?? "")
          - Status: \(response.status.code)
          - Body: \(responseBodyToLog)
          - Headers: \(Self.redactSensitiveHeaders(response.headerFields))
        """)

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

    static func redactSensitiveHeaders(_ headers: HTTPFields) -> String {
        let redacted = headers.map { field in
            if sensitiveHeaders.contains(field.name.rawName.lowercased()) {
                return "\(field.name.rawName): [REDACTED]"
            }
            return "\(field.name.rawName): \(field.value)"
        }
        return "[\(redacted.joined(separator: ", "))]"
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
