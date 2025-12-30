import Foundation
import HTTPTypes
import OpenAPIRuntime

#if os(macOS)
    import TuistSupport
#endif

public enum OutputWarningsMiddlewareError: LocalizedError {
    case couldntConvertToData
    case invalidSchema

    public var errorDescription: String? {
        switch self {
        case .couldntConvertToData:
            "We couldn't convert Tuist warnings into a data instance"
        case .invalidSchema:
            "The Tuist warnings returned by the server have an unexpected schema"
        }
    }
}

/// A middleware that gets any warning returned in a "x-tuist-cloud-warnings" header
/// and outputs it to the user.
public struct OutputWarningsMiddleware: ClientMiddleware {
    public init() {}

    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID _: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let (response, body) = try await next(request, body, baseURL)
        guard let warnings = response.headerFields.first(where: {
            $0.name.canonicalName == "x-tuist-cloud-warnings"
        })?.value
        else {
            return (response, body)
        }
        guard let warningsData = warnings.data(using: .utf8),
              let data = Data(base64Encoded: warningsData)
        else {
            throw OutputWarningsMiddlewareError.couldntConvertToData
        }

        guard let json = try JSONSerialization
            .jsonObject(with: data) as? [String]
        else {
            throw OutputWarningsMiddlewareError.invalidSchema
        }

        #if os(macOS)
            json.forEach { AlertController.current.warning(.alert("\($0)")) }
        #endif

        return (response, body)
    }
}
