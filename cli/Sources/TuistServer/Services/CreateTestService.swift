import Foundation
import Mockable
import OpenAPIURLSession
import TuistHTTP

#if canImport(TuistXCResultService)
    import TuistCI
    import TuistXCResultService

    @Mockable
    public protocol CreateTestServicing {
        func createTest(
            fullHandle: String,
            serverURL: URL,
            testSummary: TestSummary,
            buildRunId: String?,
            gitBranch: String?,
            gitCommitSHA: String?,
            gitRef: String?,
            gitRemoteURLOrigin: String?,
            isCI: Bool,
            modelIdentifier: String?,
            macOSVersion: String,
            xcodeVersion: String?,
            ciRunId: String?,
            ciProjectHandle: String?,
            ciHost: String?,
            ciProvider: CIProvider?
        ) async throws -> Components.Schemas.RunsTest
    }

    enum CreateTestServiceError: LocalizedError {
        case unknownError(Int)
        case forbidden(String)
        case notFound(String)
        case unauthorized(String)
        case badRequest(String)
        case unexpectedResponseType

        var errorDescription: String? {
            switch self {
            case let .unknownError(statusCode):
                return
                    "The test run could not be uploaded due to an unknown server response of \(statusCode)."
            case let .forbidden(message), let .notFound(message), let .unauthorized(message),
                 let .badRequest(message):
                return message
            case .unexpectedResponseType:
                return
                    "The server returned an unexpected response type. Expected a test run but received a different type."
            }
        }
    }

    public enum ServerTestRunStatus {
        case success, failure, skipped
    }

    public final class CreateTestService: CreateTestServicing {
        private let fullHandleService: FullHandleServicing

        public init(
            fullHandleService: FullHandleServicing = FullHandleService()
        ) {
            self.fullHandleService = fullHandleService
        }

        // swiftlint:disable:next function_body_length
        public func createTest(
            fullHandle: String,
            serverURL: URL,
            testSummary: TestSummary,
            buildRunId: String?,
            gitBranch: String?,
            gitCommitSHA: String?,
            gitRef: String?,
            gitRemoteURLOrigin: String?,
            isCI: Bool,
            modelIdentifier: String?,
            macOSVersion: String,
            xcodeVersion: String?,
            ciRunId: String?,
            ciProjectHandle: String?,
            ciHost: String?,
            ciProvider: CIProvider?
        ) async throws -> Components.Schemas.RunsTest {
            let client = Client.authenticated(serverURL: serverURL)
            let handles = try fullHandleService.parse(fullHandle)

            let status: Operations.createRun.Input.Body.jsonPayload.Case2Payload.statusPayload? =
                switch testSummary.status {
                case .passed:
                    .success
                case .failed:
                    .failure
                case .skipped:
                    .skipped
                }

            let testModules = testSummary.testModules.map { module in
                let testSuites = module.testSuites.map { suite in
                    Operations.createRun.Input.Body.jsonPayload.Case2Payload
                        .test_modulesPayloadPayload
                        .test_suitesPayloadPayload(
                            duration: suite.duration,
                            name: suite.name,
                            status: mapSuiteStatus(suite.status)
                        )
                }

                let moduleTestCases = module.testCases.map { testCase in
                    let failures:
                        [Operations.createRun.Input.Body.jsonPayload.Case2Payload
                            .test_modulesPayloadPayload
                            .test_casesPayloadPayload.failuresPayloadPayload
                        ] = testCase.failures
                        .map { failure in
                            Operations.createRun.Input.Body.jsonPayload.Case2Payload
                                .test_modulesPayloadPayload
                                .test_casesPayloadPayload.failuresPayloadPayload(
                                    issue_type: mapIssueType(failure.issueType),
                                    line_number: failure.lineNumber,
                                    message: failure.message,
                                    path: failure.path?.pathString
                                )
                        }

                    return Operations.createRun.Input.Body.jsonPayload.Case2Payload
                        .test_modulesPayloadPayload
                        .test_casesPayloadPayload(
                            duration: testCase.duration ?? 0,
                            failures: failures,
                            name: testCase.name,
                            status: testCaseStatusToServerStatus(testCase.status),
                            test_suite_name: testCase.testSuite
                        )
                }

                return Operations.createRun.Input.Body.jsonPayload.Case2Payload
                    .test_modulesPayloadPayload(
                        duration: module.duration,
                        name: module.name,
                        status: mapModuleStatus(module.status),
                        test_cases: moduleTestCases,
                        test_suites: testSuites
                    )
            }

            let ciProviderPayload:
                Operations.createRun.Input.Body.jsonPayload.Case2Payload.ci_providerPayload? =
                    switch ciProvider {
                    case .github:
                        .github
                    case .gitlab:
                        .gitlab
                    case .bitrise:
                        .bitrise
                    case .circleci:
                        .circleci
                    case .buildkite:
                        .buildkite
                    case .codemagic:
                        .codemagic
                    case .none:
                        nil
                    }

            let response = try await client.createRun(
                .init(
                    path: .init(
                        account_handle: handles.accountHandle,
                        project_handle: handles.projectHandle
                    ),
                    body: .json(
                        .case2(
                            .init(
                                build_run_id: buildRunId,
                                ci_host: ciHost,
                                ci_project_handle: ciProjectHandle,
                                ci_provider: ciProviderPayload,
                                ci_run_id: ciRunId,
                                duration: testSummary.duration ?? 0,
                                git_branch: gitBranch,
                                git_commit_sha: gitCommitSHA,
                                git_ref: gitRef,
                                git_remote_url_origin: gitRemoteURLOrigin,
                                is_ci: isCI,
                                macos_version: macOSVersion,
                                model_identifier: modelIdentifier,
                                scheme: testSummary.testPlanName,
                                status: status,
                                test_modules: testModules,
                                _type: .test,
                                xcode_version: xcodeVersion
                            )
                        )
                    )
                )
            )

            switch response {
            case let .ok(okResponse):
                switch okResponse.body {
                case let .json(run):
                    switch run {
                    case .RunsBuild:
                        throw CreateTestServiceError.unexpectedResponseType
                    case let .RunsTest(test):
                        return test
                    }
                }
            case let .forbidden(forbiddenResponse):
                switch forbiddenResponse.body {
                case let .json(error):
                    throw CreateTestServiceError.forbidden(error.message)
                }
            case let .undocumented(statusCode, _):
                throw CreateTestServiceError.unknownError(statusCode)
            case let .unauthorized(unauthorized):
                switch unauthorized.body {
                case let .json(error):
                    throw CreateTestServiceError.unauthorized(error.message)
                }
            case let .notFound(notFoundResponse):
                switch notFoundResponse.body {
                case let .json(error):
                    throw CreateTestServiceError.notFound(error.message)
                }
            case let .badRequest(badRequestResponse):
                switch badRequestResponse.body {
                case let .json(error):
                    throw CreateTestServiceError.badRequest(error.message)
                }
            }
        }

        private func testCaseStatusToServerStatus(_ status: TestStatus)
            -> Operations.createRun.Input.Body.jsonPayload
            .Case2Payload.test_modulesPayload.Element.test_casesPayloadPayload.statusPayload
        {
            switch status {
            case .passed:
                return .success
            case .failed:
                return .failure
            case .skipped:
                return .skipped
            }
        }

        private func mapModuleStatus(_ status: TestStatus)
            -> Operations.createRun.Input.Body.jsonPayload
            .Case2Payload.test_modulesPayloadPayload.statusPayload
        {
            switch status {
            case .passed, .skipped:
                return .success
            case .failed:
                return .failure
            }
        }

        private func mapSuiteStatus(_ status: TestStatus)
            -> Operations.createRun.Input.Body.jsonPayload
            .Case2Payload.test_modulesPayloadPayload.test_suitesPayloadPayload.statusPayload
        {
            switch status {
            case .passed, .skipped:
                return .success
            case .failed:
                return .failure
            }
        }

        private func mapIssueType(_ issueType: TestCaseFailure.IssueType?) -> Operations.createRun
            .Input.Body.jsonPayload
            .Case2Payload.test_modulesPayloadPayload.test_casesPayloadPayload.failuresPayloadPayload
            .issue_typePayload?
        {
            guard let issueType else { return nil }
            switch issueType {
            case .errorThrown:
                return .error_thrown
            case .assertionFailure:
                return .assertion_failure
            case .issueRecorded:
                return .issue_recorded
            }
        }
    }

#endif
