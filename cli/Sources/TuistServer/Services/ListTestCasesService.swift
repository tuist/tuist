import Foundation
import Mockable
import OpenAPIURLSession
import TuistHTTP

@Mockable
public protocol ListTestCasesServicing: Sendable {
    func listTestCases(
        fullHandle: String,
        name: String?,
        moduleName: String?,
        suiteName: String?,
        status: String?,
        page: Int?,
        pageSize: Int?,
        serverURL: URL
    ) async throws -> Operations.listTestCases.Output.Ok.Body.jsonPayload
}

enum ListTestCasesServiceError: LocalizedError {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The test cases could not be listed due to an unknown Tuist response of \(statusCode)."
        case let .unauthorized(message):
            return message
        case let .forbidden(message):
            return message
        }
    }
}

public final class ListTestCasesService: ListTestCasesServicing {
    private let fullHandleService: FullHandleServicing

    public convenience init() {
        self.init(
            fullHandleService: FullHandleService()
        )
    }

    init(
        fullHandleService: FullHandleServicing
    ) {
        self.fullHandleService = fullHandleService
    }

    public func listTestCases(
        fullHandle: String,
        name: String?,
        moduleName: String?,
        suiteName: String?,
        status: String?,
        page: Int?,
        pageSize: Int?,
        serverURL: URL
    ) async throws -> Operations.listTestCases.Output.Ok.Body.jsonPayload {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.listTestCases(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle
                ),
                query: .init(
                    name: name,
                    module_name: moduleName,
                    suite_name: suiteName,
                    status: status,
                    page_size: pageSize,
                    page: page
                )
            )
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(json):
                return json
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error):
                throw ListTestCasesServiceError.unauthorized(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw ListTestCasesServiceError.forbidden(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw ListTestCasesServiceError.unknownError(statusCode)
        }
    }
}
