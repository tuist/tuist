import Foundation
import OpenAPIRuntime
import TuistSupport

enum CloudClientOutputWarningsMiddlewareError: FatalError {
    var type: TuistSupport.ErrorType {
        switch self {
        case .couldntConvertToData:
            return .bug
        case .invalidSchema:
            return .bug
        }
    }

    var description: String {
        switch self {
        case .couldntConvertToData:
            "We couldn't convert Tuist warnings into a data instance"
        case .invalidSchema:
            "The Tuist warnings returned by the server have an unexpected schema"
        }
    }

    case couldntConvertToData
    case invalidSchema
}

/// A middleware that gets any warning returned in a "x-cloud-warning" header
/// and outputs it to the user.
struct ServerClientOutputWarningsMiddleware: ClientMiddleware {
    let warningController: WarningControlling

    init(warningController: WarningControlling = WarningController.shared) {
        self.warningController = warningController
    }

    func intercept(
        _ request: Request,
        baseURL: URL,
        operationID _: String,
        next: (Request, URL) async throws -> Response
    ) async throws -> Response {
        let response = try await next(request, baseURL)
        guard let warnings = response.headerFields.first(where: { $0.name.lowercased() == "x-tuist-cloud-warnings" })?.value
        else {
            return response
        }
        guard let warningsData = warnings.data(using: .utf8), let data = Data(base64Encoded: warningsData) else {
            throw CloudClientOutputWarningsMiddlewareError.couldntConvertToData
        }

        guard let json = try JSONSerialization
            .jsonObject(with: data) as? [String]
        else {
            throw CloudClientOutputWarningsMiddlewareError.invalidSchema
        }

        json.forEach { logger.warning("\($0)") }

        return response
    }
}
