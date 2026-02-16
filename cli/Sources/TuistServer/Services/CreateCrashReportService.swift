import Foundation
import Mockable
import OpenAPIRuntime
import TuistHTTP

#if canImport(TuistXCResultService)
    import TuistXCResultService

    @Mockable
    public protocol CreateCrashReportServicing {
        func createCrashReport(
            fullHandle: String,
            serverURL: URL,
            crashReport: CrashReport,
            testCaseRunId: String,
            testCaseRunAttachmentId: String
        ) async throws
    }

    enum CreateCrashReportServiceError: LocalizedError {
        case unknownError(Int)
        case forbidden(String)
        case notFound(String)
        case unauthorized(String)
        case badRequest(String)

        var errorDescription: String? {
            switch self {
            case let .unknownError(statusCode):
                return
                    "The crash report could not be created due to an unknown server response of \(statusCode)."
            case let .forbidden(message), let .notFound(message), let .unauthorized(message),
                 let .badRequest(message):
                return message
            }
        }
    }

    public struct CreateCrashReportService: CreateCrashReportServicing {
        private let fullHandleService: FullHandleServicing

        public init(
            fullHandleService: FullHandleServicing = FullHandleService()
        ) {
            self.fullHandleService = fullHandleService
        }

        public func createCrashReport(
            fullHandle: String,
            serverURL: URL,
            crashReport: CrashReport,
            testCaseRunId: String,
            testCaseRunAttachmentId: String
        ) async throws {
            let client = Client.authenticated(serverURL: serverURL)
            let handles = try fullHandleService.parse(fullHandle)

            let response = try await client.createCrashReport(
                .init(
                    path: .init(
                        account_handle: handles.accountHandle,
                        project_handle: handles.projectHandle
                    ),
                    body: .json(
                        .init(
                            exception_subtype: crashReport.exceptionSubtype,
                            exception_type: crashReport.exceptionType,
                            signal: crashReport.signal,
                            test_case_run_attachment_id: testCaseRunAttachmentId,
                            test_case_run_id: testCaseRunId,
                            triggered_thread_frames: crashReport.triggeredThreadFrames
                        )
                    )
                )
            )

            switch response {
            case .ok:
                return
            case let .forbidden(forbiddenResponse):
                switch forbiddenResponse.body {
                case let .json(error):
                    throw CreateCrashReportServiceError.forbidden(error.message)
                }
            case let .undocumented(statusCode, _):
                throw CreateCrashReportServiceError.unknownError(statusCode)
            case let .unauthorized(unauthorized):
                switch unauthorized.body {
                case let .json(error):
                    throw CreateCrashReportServiceError.unauthorized(error.message)
                }
            case let .notFound(notFoundResponse):
                switch notFoundResponse.body {
                case let .json(error):
                    throw CreateCrashReportServiceError.notFound(error.message)
                }
            case let .badRequest(badRequestResponse):
                switch badRequestResponse.body {
                case let .json(error):
                    throw CreateCrashReportServiceError.badRequest(error.message)
                }
            }
        }
    }

#endif
