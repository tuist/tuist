import Foundation
import Mockable
import OpenAPIURLSession
import TuistHTTP

#if canImport(TuistXCResultService)
    import TuistXCResultService

    @Mockable
    public protocol CreateTestCaseRunAttachmentServicing {
        func createAttachment(
            fullHandle: String,
            serverURL: URL,
            testRunId: String,
            stackTrace: CrashStackTrace
        ) async throws
    }

    enum CreateTestCaseRunAttachmentServiceError: LocalizedError {
        case unknownError(Int)
        case forbidden(String)
        case notFound(String)
        case unauthorized(String)
        case badRequest(String)
        case uploadFailed

        var errorDescription: String? {
            switch self {
            case let .unknownError(statusCode):
                return
                    "The attachment could not be uploaded due to an unknown server response of \(statusCode)."
            case let .forbidden(message), let .notFound(message), let .unauthorized(message),
                 let .badRequest(message):
                return message
            case .uploadFailed:
                return "The attachment upload to storage failed."
            }
        }
    }

    public struct CreateTestCaseRunAttachmentService: CreateTestCaseRunAttachmentServicing {
        private let fullHandleService: FullHandleServicing
        private let urlSession: URLSession

        public init(
            fullHandleService: FullHandleServicing = FullHandleService(),
            urlSession: URLSession = .tuistShared
        ) {
            self.fullHandleService = fullHandleService
            self.urlSession = urlSession
        }

        public func createAttachment(
            fullHandle: String,
            serverURL: URL,
            testRunId: String,
            stackTrace: CrashStackTrace
        ) async throws {
            let client = Client.authenticated(serverURL: serverURL)
            let handles = try fullHandleService.parse(fullHandle)
            let fileData = Data(stackTrace.rawContent.utf8)

            let response = try await client.createTestCaseRunAttachment(
                .init(
                    path: .init(
                        account_handle: handles.accountHandle,
                        project_handle: handles.projectHandle,
                        test_run_id: testRunId
                    ),
                    body: .json(
                        .init(
                            content_type: "application/x-ips",
                            file_name: stackTrace.fileName,
                            size: fileData.count,
                            test_case_run_id: stackTrace.id
                        )
                    )
                )
            )

            switch response {
            case let .created(createdResponse):
                switch createdResponse.body {
                case let .json(json):
                    guard let url = URL(string: json.upload_url) else {
                        throw CreateTestCaseRunAttachmentServiceError.uploadFailed
                    }
                    var request = URLRequest(url: url)
                    request.httpMethod = "PUT"
                    request.setValue("application/x-ips", forHTTPHeaderField: "Content-Type")
                    request.setValue(String(fileData.count), forHTTPHeaderField: "Content-Length")
                    request.httpBody = fileData

                    let (_, uploadResponse) = try await urlSession.data(for: request)
                    guard let httpResponse = uploadResponse as? HTTPURLResponse,
                          (200 ..< 300).contains(httpResponse.statusCode)
                    else {
                        throw CreateTestCaseRunAttachmentServiceError.uploadFailed
                    }
                }
            case let .forbidden(forbiddenResponse):
                switch forbiddenResponse.body {
                case let .json(error):
                    throw CreateTestCaseRunAttachmentServiceError.forbidden(error.message)
                }
            case let .undocumented(statusCode, _):
                throw CreateTestCaseRunAttachmentServiceError.unknownError(statusCode)
            case let .unauthorized(unauthorized):
                switch unauthorized.body {
                case let .json(error):
                    throw CreateTestCaseRunAttachmentServiceError.unauthorized(error.message)
                }
            case let .notFound(notFoundResponse):
                switch notFoundResponse.body {
                case let .json(error):
                    throw CreateTestCaseRunAttachmentServiceError.notFound(error.message)
                }
            case let .badRequest(badRequestResponse):
                switch badRequestResponse.body {
                case let .json(error):
                    throw CreateTestCaseRunAttachmentServiceError.badRequest(error.message)
                }
            }
        }
    }

#endif
