import Foundation
import Mockable
import OpenAPIURLSession
import TuistHTTP

#if canImport(TuistXCResultService)
    import TuistXCResultService

    @Mockable
    public protocol UploadStackTraceServicing {
        func uploadStackTraces(
            fullHandle: String,
            serverURL: URL,
            testRunId: String,
            stackTraces: [CrashStackTrace]
        ) async throws
    }

    enum UploadStackTraceServiceError: LocalizedError {
        case unknownError(Int)
        case forbidden(String)
        case notFound(String)
        case unauthorized(String)
        case badRequest(String)

        var errorDescription: String? {
            switch self {
            case let .unknownError(statusCode):
                return
                    "The stack trace could not be uploaded due to an unknown server response of \(statusCode)."
            case let .forbidden(message), let .notFound(message), let .unauthorized(message),
                 let .badRequest(message):
                return message
            }
        }
    }

    public final class UploadStackTraceService: UploadStackTraceServicing {
        private let fullHandleService: FullHandleServicing

        public init(
            fullHandleService: FullHandleServicing = FullHandleService()
        ) {
            self.fullHandleService = fullHandleService
        }

        public func uploadStackTraces(
            fullHandle: String,
            serverURL: URL,
            testRunId: String,
            stackTraces: [CrashStackTrace]
        ) async throws {
            let client = Client.authenticated(serverURL: serverURL)
            let handles = try fullHandleService.parse(fullHandle)

            try await withThrowingTaskGroup(of: Void.self) { group in
                for stackTrace in stackTraces {
                    group.addTask {
                        try await self.uploadSingleStackTrace(
                            client: client,
                            accountHandle: handles.accountHandle,
                            projectHandle: handles.projectHandle,
                            testRunId: testRunId,
                            stackTrace: stackTrace
                        )
                    }
                }
                try await group.waitForAll()
            }
        }

        private func uploadSingleStackTrace(
            client: Client,
            accountHandle: String,
            projectHandle: String,
            testRunId: String,
            stackTrace: CrashStackTrace
        ) async throws {
            let response = try await client.uploadStackTrace(
                .init(
                    path: .init(
                        account_handle: accountHandle,
                        project_handle: projectHandle,
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
                            raw_content: stackTrace.rawContent,
                            signal: stackTrace.signal
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
                    throw UploadStackTraceServiceError.forbidden(error.message)
                }
            case let .undocumented(statusCode, _):
                throw UploadStackTraceServiceError.unknownError(statusCode)
            case let .unauthorized(unauthorized):
                switch unauthorized.body {
                case let .json(error):
                    throw UploadStackTraceServiceError.unauthorized(error.message)
                }
            case let .notFound(notFoundResponse):
                switch notFoundResponse.body {
                case let .json(error):
                    throw UploadStackTraceServiceError.notFound(error.message)
                }
            case let .badRequest(badRequestResponse):
                switch badRequestResponse.body {
                case let .json(error):
                    throw UploadStackTraceServiceError.badRequest(error.message)
                }
            }
        }
    }

#endif
