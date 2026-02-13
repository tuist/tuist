import Foundation
import Mockable
import OpenAPIURLSession
import TuistHTTP

public typealias ServerTestRun = Operations.getTestRun.Output.Ok.Body.jsonPayload

@Mockable
public protocol GetTestRunServicing: Sendable {
    func getTestRun(
        fullHandle: String,
        testRunId: String,
        serverURL: URL
    ) async throws -> ServerTestRun
}

enum GetTestRunServiceError: LocalizedError {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The test run could not be fetched due to an unknown Tuist response of \(statusCode)."
        case let .notFound(message):
            return message
        case let .forbidden(message):
            return message
        }
    }
}

public struct GetTestRunService: GetTestRunServicing {
    private let fullHandleService: FullHandleServicing

    public init(fullHandleService: FullHandleServicing = FullHandleService()) {
        self.fullHandleService = fullHandleService
    }

    public func getTestRun(
        fullHandle: String,
        testRunId: String,
        serverURL: URL
    ) async throws -> ServerTestRun {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        let response = try await client.getTestRun(
            .init(
                path: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle,
                    test_run_id: testRunId
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
                throw GetTestRunServiceError.notFound(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error):
                throw GetTestRunServiceError.forbidden(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw GetTestRunServiceError.unknownError(statusCode)
        }
    }
}

#if DEBUG
    extension ServerTestRun {
        public static func test(
            avgTestDuration: Int = 120,
            deviceName: String? = "MacBook Pro (16-inch, 2021)",
            duration: Int = 1500,
            failedTestCount: Int = 0,
            flakyTestCount: Int = 0,
            gitBranch: String? = "main",
            gitCommitSha: String? = "abc1234",
            id: String = "run-id",
            isCi: Bool = true,
            isFlaky: Bool = false,
            macosVersion: String? = "14.0",
            modelIdentifier: String? = "MacBookPro18,3",
            ranAt: Date? = Date(timeIntervalSince1970: 1_700_000_000),
            scheme: String? = "App",
            status: Operations.getTestRun.Output.Ok.Body.jsonPayload.statusPayload = .success,
            totalTestCount: Int = 42,
            xcodeVersion: String? = "15.0"
        ) -> Self {
            .init(
                avg_test_duration: avgTestDuration,
                device_name: deviceName,
                duration: duration,
                failed_test_count: failedTestCount,
                flaky_test_count: flakyTestCount,
                git_branch: gitBranch,
                git_commit_sha: gitCommitSha,
                id: id,
                is_ci: isCi,
                is_flaky: isFlaky,
                macos_version: macosVersion,
                model_identifier: modelIdentifier,
                ran_at: ranAt,
                scheme: scheme,
                status: status,
                total_test_count: totalTestCount,
                xcode_version: xcodeVersion
            )
        }
    }
#endif
