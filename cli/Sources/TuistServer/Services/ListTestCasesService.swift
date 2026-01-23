import Foundation
import Mockable
import OpenAPIURLSession
import TuistHTTP

@Mockable
public protocol ListTestCasesServicing {
    func listTestCases(
        fullHandle: String,
        serverURL: URL,
        flaky: Bool?,
        quarantined: Bool?,
        page: Int?,
        pageSize: Int
    ) async throws -> Operations.listTestCases.Output.Ok.Body.jsonPayload
}

enum ListTestCasesServiceError: LocalizedError {
    case unknownError(Int)
    case forbidden(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "We could not list the test cases due to an unknown Tuist response of \(statusCode)."
        case let .forbidden(message):
            return message
        }
    }
}

public struct ListTestCasesService: ListTestCasesServicing {
    private let fullHandleService: FullHandleServicing

    public init() {
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
        serverURL: URL,
        flaky: Bool?,
        quarantined: Bool?,
        page: Int?,
        pageSize: Int
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
                    flaky: flaky,
                    quarantined: quarantined,
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
