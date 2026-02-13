import Foundation
import Mockable
import OpenAPIURLSession
import TuistHTTP

@Mockable
public protocol ListTestCaseRunsByTestRunServicing {
    func listTestCaseRunsByTestRun(
        fullHandle: String,
        serverURL: URL,
        testRunId: String,
        page: Int?,
        pageSize: Int
    ) async throws -> Operations.listTestCaseRunsByTestRun.Output.Ok.Body.jsonPayload
}

enum ListTestCaseRunsByTestRunServiceError: LocalizedError {
    case unknownError(Int)
    case forbidden(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "We could not list the test case runs due to an unknown Tuist response of \(statusCode)."
        case let .forbidden(message):
            return message
        }
    }
}

public struct ListTestCaseRunsByTestRunService: ListTestCaseRunsByTestRunServicing {
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

    public func listTestCaseRunsByTestRun(
        fullHandle: String,
        serverURL: URL,
        testRunId: String,
        page: Int?,
        pageSize: Int
    ) async throws -> Operations.listTestCaseRunsByTestRun.Output.Ok.Body.jsonPayload {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.listTestCaseRunsByTestRun(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    test_run_id: testRunId
                ),
                query: .init(
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
                throw ListTestCaseRunsByTestRunServiceError.forbidden(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw ListTestCaseRunsByTestRunServiceError.unknownError(statusCode)
        }
    }
}

#if DEBUG
    extension Operations.listTestCaseRunsByTestRun.Output.Ok.Body.jsonPayload {
        public static func test(
            currentPage: Int = 1,
            pageSize: Int = 10,
            totalPages: Int = 1,
            hasNextPage: Bool = false,
            hasPreviousPage: Bool = false,
            testCaseRuns: [Operations.listTestCaseRunsByTestRun.Output.Ok.Body.jsonPayload
                .test_case_runsPayloadPayload]
        ) -> Self {
            .init(
                pagination_metadata: .init(
                    current_page: currentPage,
                    has_next_page: hasNextPage,
                    has_previous_page: hasPreviousPage,
                    page_size: pageSize,
                    total_count: testCaseRuns.count,
                    total_pages: totalPages
                ),
                test_case_runs: testCaseRuns
            )
        }
    }

    extension Operations.listTestCaseRunsByTestRun.Output.Ok.Body.jsonPayload
        .test_case_runsPayloadPayload
    {
        public static func test(
            duration: Int = 1500,
            id: String = "run-id",
            isCi: Bool = true,
            isFlaky: Bool = false,
            isNew: Bool = false,
            moduleName: String = "AppTests",
            name: String = "testExample",
            status: Operations.listTestCaseRunsByTestRun.Output.Ok.Body.jsonPayload
                .test_case_runsPayloadPayload.statusPayload = .success,
            suiteName: String? = nil
        ) -> Self {
            .init(
                duration: duration,
                id: id,
                is_ci: isCi,
                is_flaky: isFlaky,
                is_new: isNew,
                module_name: moduleName,
                name: name,
                status: status,
                suite_name: suiteName
            )
        }
    }
#endif
