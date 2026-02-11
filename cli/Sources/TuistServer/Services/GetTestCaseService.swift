import Foundation
import Mockable
import OpenAPIURLSession
import TuistHTTP

public typealias ServerTestCase = Operations.getTestCase.Output.Ok.Body.jsonPayload

@Mockable
public protocol GetTestCaseServicing: Sendable {
    func getTestCase(
        fullHandle: String,
        testCaseId: String,
        serverURL: URL
    ) async throws -> ServerTestCase

    func getTestCaseByName(
        fullHandle: String,
        moduleName: String,
        name: String,
        suiteName: String?,
        serverURL: URL
    ) async throws -> ServerTestCase
}

enum GetTestCaseServiceError: LocalizedError {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The test case could not be fetched due to an unknown Tuist response of \(statusCode)."
        case let .notFound(message):
            return message
        case let .forbidden(message):
            return message
        }
    }
}

public struct GetTestCaseService: GetTestCaseServicing {
    private let fullHandleService: FullHandleServicing

    public init(fullHandleService: FullHandleServicing = FullHandleService()) {
        self.fullHandleService = fullHandleService
    }

    public func getTestCase(
        fullHandle: String,
        testCaseId: String,
        serverURL: URL
    ) async throws -> ServerTestCase {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.getTestCase(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    test_case_id: testCaseId
                )
            )
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(json):
                return json
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error):
                throw GetTestCaseServiceError.notFound(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw GetTestCaseServiceError.forbidden(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw GetTestCaseServiceError.unknownError(statusCode)
        }
    }

    public func getTestCaseByName(
        fullHandle: String,
        moduleName: String,
        name: String,
        suiteName: String?,
        serverURL: URL
    ) async throws -> ServerTestCase {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.listTestCases(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle
                ),
                query: .init(
                    module_name: moduleName,
                    name: name,
                    suite_name: suiteName,
                    page_size: 1,
                    page: 1
                )
            )
        )

        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(json):
                guard let testCase = json.test_cases.first else {
                    throw GetTestCaseServiceError.notFound("Test case not found.")
                }
                return try await getTestCase(
                    fullHandle: fullHandle,
                    testCaseId: testCase.id,
                    serverURL: serverURL
                )
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw GetTestCaseServiceError.forbidden(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw GetTestCaseServiceError.unknownError(statusCode)
        }
    }
}

#if DEBUG
    extension ServerTestCase {
        public static func test(
            avgDuration: Int = 100,
            failedRuns: Int = 2,
            flakinessRate: Double = 5.0,
            id: String = "test-case-id",
            isFlaky: Bool = false,
            isQuarantined: Bool = false,
            lastDuration: Int = 150,
            lastRanAt: Int = 1_700_000_000,
            lastStatus: Operations.getTestCase.Output.Ok.Body.jsonPayload.last_statusPayload = .success,
            module: Operations.getTestCase.Output.Ok.Body.jsonPayload.modulePayload = .test(),
            name: String = "testExample",
            reliabilityRate: Double? = 95.0,
            suite: Operations.getTestCase.Output.Ok.Body.jsonPayload.suitePayload? = nil,
            totalRuns: Int = 50,
            url: String = "https://tuist.dev/test-case"
        ) -> Self {
            .init(
                avg_duration: avgDuration,
                failed_runs: failedRuns,
                flakiness_rate: flakinessRate,
                id: id,
                is_flaky: isFlaky,
                is_quarantined: isQuarantined,
                last_duration: lastDuration,
                last_ran_at: lastRanAt,
                last_status: lastStatus,
                module: module,
                name: name,
                reliability_rate: reliabilityRate,
                suite: suite,
                total_runs: totalRuns,
                url: url
            )
        }
    }

    extension Operations.getTestCase.Output.Ok.Body.jsonPayload.modulePayload {
        public static func test(
            id: String = "module-id",
            name: String = "TestModule"
        ) -> Self {
            .init(id: id, name: name)
        }
    }

    extension Operations.getTestCase.Output.Ok.Body.jsonPayload.suitePayload {
        public static func test(
            id: String = "suite-id",
            name: String = "TestSuite"
        ) -> Self {
            .init(id: id, name: name)
        }
    }
#endif
