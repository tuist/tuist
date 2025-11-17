import Foundation
import Mockable
import OpenAPIURLSession

#if canImport(TuistXCResultService)
    import TuistXCResultService

    @Mockable
    public protocol CreateTestServicing {
        func createTest(
            fullHandle: String,
            serverURL: URL,
            id: String,
            testSummary: TestSummary,
            gitBranch: String?,
            gitCommitSHA: String?,
            gitRef: String?,
            gitRemoteURLOrigin: String?,
            isCI: Bool,
            modelIdentifier: String?,
            macOSVersion: String,
            xcodeVersion: String?
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

        public func createTest(
            fullHandle: String,
            serverURL: URL,
            id: String,
            testSummary: TestSummary,
            gitBranch: String?,
            gitCommitSHA: String?,
            gitRef: String?,
            gitRemoteURLOrigin: String?,
            isCI: Bool,
            modelIdentifier: String?,
            macOSVersion: String,
            xcodeVersion: String?
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
                    .success // Map skipped to success for overall run status
                }

            // Group test cases by module (target)
            let testCasesByModule = Dictionary(grouping: testSummary.testCases) { testCase in
                testCase.module ?? "Unknown"
            }
            
            let testModules = testCasesByModule.map { (moduleName, testCases) in
                // Calculate module status and duration
                let moduleStatus: Operations.createRun.Input.Body.jsonPayload.Case2Payload.test_modulesPayloadPayload.statusPayload = 
                    testCases.contains { testCaseStatusToServerStatus($0.status) == .failure } ? .failure : .success
                let moduleDuration = testCases.compactMap { $0.duration }.reduce(0, +)
                
                // Group test cases by test suite within this module
                let testCasesBySuite = Dictionary(grouping: testCases) { testCase in
                    testCase.testSuite
                }
                
                // Create test suites with their test cases
                let testSuites = testCasesBySuite.compactMap { (suiteName, suiteTestCases) -> Operations.createRun.Input.Body.jsonPayload.Case2Payload.test_modulesPayloadPayload.test_suitesPayloadPayload? in
                    guard let suiteName = suiteName else { return nil }
                    let suiteStatus: Operations.createRun.Input.Body.jsonPayload.Case2Payload.test_modulesPayloadPayload.test_suitesPayloadPayload.statusPayload =
                        suiteTestCases.contains { testCaseStatusToServerStatus($0.status) == .failure } ? .failure : .success
                    let suiteDuration = suiteTestCases.compactMap { $0.duration }.reduce(0, +)
                    
                    return Operations.createRun.Input.Body.jsonPayload.Case2Payload.test_modulesPayloadPayload.test_suitesPayloadPayload(
                        duration: suiteDuration,
                        name: suiteName,
                        status: suiteStatus
                    )
                }
                
                // Create all test cases for this module
                let moduleTestCases = testCases.map { testCase in
                    Operations.createRun.Input.Body.jsonPayload.Case2Payload.test_modulesPayloadPayload.test_casesPayloadPayload(
                        duration: testCase.duration ?? 0,
                        name: testCase.name,
                        status: testCaseStatusToServerStatus(testCase.status),
                        test_suite_name: testCase.testSuite
                    )
                }
                
                return Operations.createRun.Input.Body.jsonPayload.Case2Payload.test_modulesPayloadPayload(
                    duration: moduleDuration,
                    name: moduleName,
                    status: moduleStatus,
                    test_cases: moduleTestCases,
                    test_suites: testSuites
                )
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
                                duration: testSummary.duration ?? 0,
                                git_branch: gitBranch,
                                git_commit_sha: gitCommitSHA,
                                git_ref: gitRef,
                                git_remote_url_origin: gitRemoteURLOrigin,
                                id: id,
                                is_ci: isCI,
                                macos_version: macOSVersion,
                                model_identifier: modelIdentifier,
                                scheme: testSummary.scheme,
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
                        fatalError()
                    case let .RunsTest(test):
                        return test
                    }
                }
            case let .forbidden(forbiddenResponse):
                switch forbiddenResponse.body {
                case let .json(error):
                    throw CreateTestServiceError.forbidden(error.message)
                }
            case let .undocumented(statusCode: statusCode, _):
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
        
        private func testCaseStatusToServerStatus(_ status: TestStatus) -> Operations.createRun.Input.Body.jsonPayload.Case2Payload.test_modulesPayload.Element.test_casesPayloadPayload.statusPayload {
            switch status {
            case .passed:
                return .success
            case .failed:
                return .failure
            case .skipped:
                return .skipped
            }
        }
    }

#endif
