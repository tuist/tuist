import Foundation
import Mockable
import OpenAPIRuntime
import Path
import TuistHTTP

/// Coverage a client uploaded to object storage instead of sending inline with the run: the key
/// the server handed out for the run's id, and whether the run left tests out on purpose.
public struct XcodeCoverageUpload: Equatable, Sendable {
    public let storageKey: String
    public let partial: Bool

    public init(storageKey: String, partial: Bool) {
        self.storageKey = storageKey
        self.partial = partial
    }
}

enum CoverageUploadServiceError: LocalizedError {
    case unknownError(Int)
    case notFound(String)
    case forbidden(String)
    case unauthorized(String)
    case invalidUploadURL(String)
    case uploadFailed(Int)

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The coverage upload request failed with an unknown Tuist response of \(statusCode)."
        case let .forbidden(message), let .notFound(message), let .unauthorized(message):
            return message
        case let .invalidUploadURL(url):
            return "The coverage upload URL is invalid: \(url)"
        case let .uploadFailed(statusCode):
            return "The coverage upload was rejected with status \(statusCode)."
        }
    }
}

@Mockable
public protocol GetCoverageSettingsServicing {
    /// The size, in bytes of the compressed coverage, above which it goes through an upload.
    func inlineThresholdBytes(fullHandle: String, serverURL: URL) async throws -> Int
}

public struct GetCoverageSettingsService: GetCoverageSettingsServicing {
    private let fullHandleService: FullHandleServicing

    public init(fullHandleService: FullHandleServicing = FullHandleService()) {
        self.fullHandleService = fullHandleService
    }

    public func inlineThresholdBytes(fullHandle: String, serverURL: URL) async throws -> Int {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)
        let response = try await client.getCoverageSettings(
            .init(path: .init(account_handle: handles.accountHandle, project_handle: handles.projectHandle))
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(settings): return settings.inline_threshold_bytes
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error): throw CoverageUploadServiceError.notFound(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error): throw CoverageUploadServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error): throw CoverageUploadServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw CoverageUploadServiceError.unknownError(statusCode)
        }
    }
}

@Mockable
public protocol CreateCoverageUploadServicing {
    /// Where to PUT the compressed coverage of the run the client is about to create with `testRunId`.
    func createCoverageUpload(
        fullHandle: String,
        serverURL: URL,
        testRunId: String
    ) async throws -> (storageKey: String, uploadURL: URL)
}

public struct CreateCoverageUploadService: CreateCoverageUploadServicing {
    private let fullHandleService: FullHandleServicing

    public init(fullHandleService: FullHandleServicing = FullHandleService()) {
        self.fullHandleService = fullHandleService
    }

    public func createCoverageUpload(
        fullHandle: String,
        serverURL: URL,
        testRunId: String
    ) async throws -> (storageKey: String, uploadURL: URL) {
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)
        let response = try await client.createCoverageUpload(
            .init(
                path: .init(account_handle: handles.accountHandle, project_handle: handles.projectHandle),
                body: .json(.init(test_run_id: testRunId))
            )
        )
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case let .json(upload):
                guard let url = URL(string: upload.upload_url) else {
                    throw CoverageUploadServiceError.invalidUploadURL(upload.upload_url)
                }
                return (storageKey: upload.storage_key, uploadURL: url)
            }
        case let .notFound(notFound):
            switch notFound.body {
            case let .json(error): throw CoverageUploadServiceError.notFound(error.message)
            }
        case let .forbidden(forbidden):
            switch forbidden.body {
            case let .json(error): throw CoverageUploadServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            switch unauthorized.body {
            case let .json(error): throw CoverageUploadServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode: statusCode, _):
            throw CoverageUploadServiceError.unknownError(statusCode)
        }
    }
}

@Mockable
public protocol CoverageFileUploading {
    /// PUTs the file to the signed URL, streaming it from disk.
    func upload(file: AbsolutePath, to url: URL) async throws
}

public struct CoverageFileUploader: CoverageFileUploading {
    private let urlSession: URLSession

    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    public func upload(file: AbsolutePath, to url: URL) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await urlSession.upload(for: request, fromFile: URL(fileURLWithPath: file.pathString))
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw CoverageUploadServiceError.uploadFailed((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }
}
