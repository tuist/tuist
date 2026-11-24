import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

/// Reads a test run's coverage-based selection: the tests it decided and the files that changed since its baseline.
@Mockable
public protocol SelectiveTestingServicing: Sendable {
    func listTests(
        fullHandle: String,
        serverURL: URL,
        testRunId: String,
        decision: String?,
        reason: String?,
        search: String?,
        page: Int?,
        pageSize: Int?
    ) async throws -> Operations.listTestRunSelectiveTestingTests.Output.Ok.Body.jsonPayload

    func listChangedFiles(
        fullHandle: String,
        serverURL: URL,
        testRunId: String,
        search: String?,
        page: Int?,
        pageSize: Int?
    ) async throws -> Operations.listTestRunSelectiveTestingChangedFiles.Output.Ok.Body.jsonPayload
}

enum SelectiveTestingServiceError: LocalizedError, Equatable {
    case forbidden(String)
    case notFound(String)
    case unknownError(Int)

    var errorDescription: String? {
        switch self {
        case let .forbidden(message), let .notFound(message):
            return message
        case let .unknownError(statusCode):
            return "We could not read the test run's selective testing due to an unknown Tuist response of \(statusCode)."
        }
    }
}

public struct SelectiveTestingService: SelectiveTestingServicing {
    private let makeClient: @Sendable (URL) -> Client

    public init() {
        self.init(makeClient: { Client.authenticated(serverURL: $0) })
    }

    init(makeClient: @escaping @Sendable (URL) -> Client) {
        self.makeClient = makeClient
    }

    public func listTests(
        fullHandle: String,
        serverURL: URL,
        testRunId: String,
        decision: String?,
        reason: String?,
        search: String?,
        page: Int?,
        pageSize: Int?
    ) async throws -> Operations.listTestRunSelectiveTestingTests.Output.Ok.Body.jsonPayload {
        let handles = try FullHandleService().parse(fullHandle)
        let response = try await makeClient(serverURL).listTestRunSelectiveTestingTests(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    test_run_id: testRunId
                ),
                query: .init(
                    decision: decision.flatMap {
                        Operations.listTestRunSelectiveTestingTests.Input.Query.decisionPayload(rawValue: $0)
                    },
                    reason: reason,
                    search: search,
                    page: page,
                    page_size: pageSize
                )
            )
        )
        switch response {
        case let .ok(value): return try value.body.json
        case let .forbidden(value): throw SelectiveTestingServiceError.forbidden(try value.body.json.message)
        case let .notFound(value): throw SelectiveTestingServiceError.notFound(try value.body.json.message)
        case let .tooManyRequests(value):
            throw AuthorizationThrottledError(retryAfterSeconds: value.headers.retry_hyphen_after.flatMap(Int.init))
        case let .undocumented(statusCode, _): throw SelectiveTestingServiceError.unknownError(statusCode)
        }
    }

    public func listChangedFiles(
        fullHandle: String,
        serverURL: URL,
        testRunId: String,
        search: String?,
        page: Int?,
        pageSize: Int?
    ) async throws -> Operations.listTestRunSelectiveTestingChangedFiles.Output.Ok.Body.jsonPayload {
        let handles = try FullHandleService().parse(fullHandle)
        let response = try await makeClient(serverURL).listTestRunSelectiveTestingChangedFiles(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    test_run_id: testRunId
                ),
                query: .init(search: search, page: page, page_size: pageSize)
            )
        )
        switch response {
        case let .ok(value): return try value.body.json
        case let .forbidden(value): throw SelectiveTestingServiceError.forbidden(try value.body.json.message)
        case let .notFound(value): throw SelectiveTestingServiceError.notFound(try value.body.json.message)
        case let .tooManyRequests(value):
            throw AuthorizationThrottledError(retryAfterSeconds: value.headers.retry_hyphen_after.flatMap(Int.init))
        case let .undocumented(statusCode, _): throw SelectiveTestingServiceError.unknownError(statusCode)
        }
    }
}
