import Foundation
import Mockable
import OpenAPIURLSession
import TuistHTTP

#if canImport(TuistXCResultService)
    import TuistXCResultService

    @Mockable
    public protocol UploadTestCaseRunAttachmentServicing {
        func uploadAttachments(
            fullHandle: String,
            serverURL: URL,
            testRunId: String,
            stackTraces: [CrashStackTrace]
        ) async throws
    }

    enum UploadTestCaseRunAttachmentServiceError: LocalizedError {
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

    public final class UploadTestCaseRunAttachmentService: UploadTestCaseRunAttachmentServicing {
        private let fullHandleService: FullHandleServicing
        private let urlSession: URLSession

        public convenience init() {
            self.init(
                fullHandleService: FullHandleService(),
                urlSession: .tuistShared
            )
        }

        init(
            fullHandleService: FullHandleServicing,
            urlSession: URLSession
        ) {
            self.fullHandleService = fullHandleService
            self.urlSession = urlSession
        }

        public func uploadAttachments(
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
                        try await self.uploadSingleAttachment(
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

        private func uploadSingleAttachment(
            client: Client,
            accountHandle: String,
            projectHandle: String,
            testRunId: String,
            stackTrace: CrashStackTrace
        ) async throws {
            let fileData = Data(stackTrace.rawContent.utf8)

            let response = try await client.createTestCaseRunAttachment(
                .init(
                    path: .init(
                        account_handle: accountHandle,
                        project_handle: projectHandle,
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
                        throw UploadTestCaseRunAttachmentServiceError.uploadFailed
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
                        throw UploadTestCaseRunAttachmentServiceError.uploadFailed
                    }
                }
            case let .forbidden(forbiddenResponse):
                switch forbiddenResponse.body {
                case let .json(error):
                    throw UploadTestCaseRunAttachmentServiceError.forbidden(error.message)
                }
            case let .undocumented(statusCode, _):
                throw UploadTestCaseRunAttachmentServiceError.unknownError(statusCode)
            case let .unauthorized(unauthorized):
                switch unauthorized.body {
                case let .json(error):
                    throw UploadTestCaseRunAttachmentServiceError.unauthorized(error.message)
                }
            case let .notFound(notFoundResponse):
                switch notFoundResponse.body {
                case let .json(error):
                    throw UploadTestCaseRunAttachmentServiceError.notFound(error.message)
                }
            case let .badRequest(badRequestResponse):
                switch badRequestResponse.body {
                case let .json(error):
                    throw UploadTestCaseRunAttachmentServiceError.badRequest(error.message)
                }
            }
        }
    }

#endif
