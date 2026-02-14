import Foundation
import Mockable
import OpenAPIURLSession
import TuistHTTP

#if canImport(TuistXCResultService)
    import TuistXCResultService

    @Mockable
    public protocol CreateStackTraceServicing {
        func createStackTrace(
            fullHandle: String,
            serverURL: URL,
            testRunId: String,
            stackTrace: CrashStackTrace,
            testCaseRunId: String?,
            testCaseRunAttachmentId: String?
        ) async throws
    }

    enum CreateStackTraceServiceError: LocalizedError {
        case unknownError(Int)
        case forbidden(String)
        case notFound(String)
        case unauthorized(String)
        case badRequest(String)

        var errorDescription: String? {
            switch self {
            case let .unknownError(statusCode):
                return
                    "The stack trace could not be created due to an unknown server response of \(statusCode)."
            case let .forbidden(message), let .notFound(message), let .unauthorized(message),
                 let .badRequest(message):
                return message
            }
        }
    }

    public struct CreateStackTraceService: CreateStackTraceServicing {
        private let fullHandleService: FullHandleServicing

        public init(
            fullHandleService: FullHandleServicing = FullHandleService()
        ) {
            self.fullHandleService = fullHandleService
        }

        public func createStackTrace(
            fullHandle: String,
            serverURL: URL,
            testRunId: String,
            stackTrace: CrashStackTrace,
            testCaseRunId: String? = nil,
            testCaseRunAttachmentId: String? = nil
        ) async throws {
            let client = Client.authenticated(serverURL: serverURL)
            let handles = try fullHandleService.parse(fullHandle)

            let response = try await client.createStackTrace(
                .init(
                    path: .init(
                        account_handle: handles.accountHandle,
                        project_handle: handles.projectHandle,
                        test_run_id: testRunId
                    ),
                    body: .json(
                        .init(
                            app_name: stackTrace.appName,
                            exception_subtype: stackTrace.exceptionSubtype,
                            exception_type: stackTrace.exceptionType,
                            file_name: stackTrace.fileName,
                            id: stackTrace.id,
                            os_version: stackTrace.osVersion,
                            signal: stackTrace.signal,
                            test_case_run_attachment_id: testCaseRunAttachmentId,
                            test_case_run_id: testCaseRunId,
                            triggered_thread_frames: stackTrace.triggeredThreadFrames
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
                    throw CreateStackTraceServiceError.forbidden(error.message)
                }
            case let .undocumented(statusCode, _):
                throw CreateStackTraceServiceError.unknownError(statusCode)
            case let .unauthorized(unauthorized):
                switch unauthorized.body {
                case let .json(error):
                    throw CreateStackTraceServiceError.unauthorized(error.message)
                }
            case let .notFound(notFoundResponse):
                switch notFoundResponse.body {
                case let .json(error):
                    throw CreateStackTraceServiceError.notFound(error.message)
                }
            case let .badRequest(badRequestResponse):
                switch badRequestResponse.body {
                case let .json(error):
                    throw CreateStackTraceServiceError.badRequest(error.message)
                }
            }
        }
    }

#endif
