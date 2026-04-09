import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

#if canImport(TuistXCResultService)
    import TuistCI
    import TuistXCResultService
    import XCResultParser

    @Mockable
    public protocol CreateTestServicing {
        func createTest(
            fullHandle: String,
            serverURL: URL,
            id: String?,
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
            ciProvider: CIProvider?,
            shardPlanId: String?,
            shardIndex: Int?
        ) async throws -> Components.Schemas.RunsTest
    }

    enum CreateTestServiceError: LocalizedError {
        case unknownError(Int)
        case forbidden(String)
        case notFound(String)
        case unauthorized(String)
        case badRequest(String)

        var errorDescription: String? {
            switch self {
            case let .unknownError(statusCode):
                return
                    "The test run could not be uploaded due to an unknown server response of \(statusCode)."
            case let .forbidden(message), let .notFound(message), let .unauthorized(message),
                 let .badRequest(message):
                return message
            }
        }
    }

    public struct CreateTestService: CreateTestServicing {
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
            id: String? = nil,
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
            ciProvider: CIProvider?,
            shardPlanId: String?,
            shardIndex: Int?
        ) async throws -> Components.Schemas.RunsTest {
            let client = Client.authenticated(serverURL: serverURL)
            let handles = try fullHandleService.parse(fullHandle)

            let status: Operations.createTest.Input.Body.jsonPayload.statusPayload? =
                switch testSummary.status {
                case .passed:
                    .success
                case .failed:
                    .failure
                case .skipped:
                    .skipped
                case .processing:
                    .processing
                }

            let testModules = testSummary.testModules.map { module in
                let testSuites = module.testSuites.map { suite in
                    Operations.createTest.Input.Body.jsonPayload
                        .test_modulesPayloadPayload
                        .test_suitesPayloadPayload(
                            duration: suite.duration,
                            name: suite.name,
                            status: mapSuiteStatus(suite.status)
                        )
                }

                let moduleTestCases = module.testCases.map { testCase in
                    let failures: [Components.Schemas.TestCaseFailure] = testCase.failures
                        .map { failure in
                            Components.Schemas.TestCaseFailure(
                                issue_type: mapIssueType(failure.issueType),
                                line_number: failure.lineNumber,
                                message: failure.message,
                                path: failure.path?.pathString
                            )
                        }

                    let repetitions: [Components.Schemas.TestCaseRepetition] = testCase.repetitions
                        .map { repetition in
                            Components.Schemas.TestCaseRepetition(
                                duration: repetition.duration,
                                name: repetition.name,
                                repetition_number: repetition.repetitionNumber,
                                status: repetitionStatusToServerStatus(repetition.status)
                            )
                        }

                    let arguments = testCase.arguments.map { argument in
                        let argFailures = argument.failures.map { failure in
                            Components.Schemas.TestCaseFailure(
                                issue_type: mapIssueType(failure.issueType),
                                line_number: failure.lineNumber,
                                message: failure.message,
                                path: failure.path?.pathString
                            )
                        }
                        let argRepetitions = argument.repetitions.map { repetition in
                            Components.Schemas.TestCaseRepetition(
                                duration: repetition.duration,
                                name: repetition.name,
                                repetition_number: repetition.repetitionNumber,
                                status: repetitionStatusToServerStatus(repetition.status)
                            )
                        }
                        return Operations.createTest.Input.Body.jsonPayload
                            .test_modulesPayloadPayload
                            .test_casesPayloadPayload.argumentsPayloadPayload(
                                duration: argument.duration,
                                failures: argFailures,
                                name: argument.name,
                                repetitions: argRepetitions,
                                status: argument.status == .failed ? .failure : .success
                            )
                    }

                    return Operations.createTest.Input.Body.jsonPayload
                        .test_modulesPayloadPayload
                        .test_casesPayloadPayload(
                            arguments: arguments,
                            duration: testCase.duration ?? 0,
                            failures: failures,
                            is_quarantined: testCase.isQuarantined,
                            name: testCase.name,
                            repetitions: repetitions,
                            status: testCaseStatusToServerStatus(testCase.status),
                            test_suite_name: testCase.testSuite
                        )
                }

                return Operations.createTest.Input.Body.jsonPayload
                    .test_modulesPayloadPayload(
                        duration: module.duration,
                        name: module.name,
                        status: mapModuleStatus(module.status),
                        test_cases: moduleTestCases,
                        test_suites: testSuites
                    )
            }

            let ciProviderPayload:
                Operations.createTest.Input.Body.jsonPayload.ci_providerPayload? =
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

            let response = try await client.createTest(
                .init(
                    path: .init(
                        account_handle: handles.accountHandle,
                        project_handle: handles.projectHandle
                    ),
                    body: .json(
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
                            id: id,
                            is_ci: isCI,
                            macos_version: macOSVersion,
                            model_identifier: modelIdentifier,
                            scheme: testSummary.testPlanName,
                            shard_index: shardIndex,
                            shard_plan_id: shardPlanId,
                            status: status,
                            test_modules: testModules,
                            xcode_version: xcodeVersion
                        )
                    )
                )
            )

            switch response {
            case let .ok(okResponse):
                switch okResponse.body {
                case let .json(test):
                    return test
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
            -> Operations.createTest.Input.Body.jsonPayload
            .test_modulesPayload.Element.test_casesPayloadPayload.statusPayload
        {
            switch status {
            case .passed, .processing:
                return .success
            case .failed:
                return .failure
            case .skipped:
                return .skipped
            }
        }

        private func mapModuleStatus(_ status: TestStatus)
            -> Operations.createTest.Input.Body.jsonPayload
            .test_modulesPayloadPayload.statusPayload
        {
            switch status {
            case .passed, .skipped, .processing:
                return .success
            case .failed:
                return .failure
            }
        }

        private func mapSuiteStatus(_ status: TestStatus)
            -> Operations.createTest.Input.Body.jsonPayload
            .test_modulesPayloadPayload.test_suitesPayloadPayload.statusPayload
        {
            switch status {
            case .passed, .skipped, .processing:
                return .success
            case .failed:
                return .failure
            }
        }

        private func mapIssueType(_ issueType: TestCaseFailure.IssueType?)
            -> Components.Schemas.TestCaseFailure.issue_typePayload?
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

        private func repetitionStatusToServerStatus(_ status: TestStatus)
            -> Components.Schemas.TestCaseRepetition.statusPayload
        {
            switch status {
            case .passed, .skipped, .processing:
                return .success
            case .failed:
                return .failure
            }
        }
    }

#endif
