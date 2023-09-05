import Foundation
import TuistSupport

public protocol VerifyCacheUploadServicing {
    func verifyCacheUpload(
        serverURL: URL,
        projectId: String,
        hash: String,
        name: String,
        contentMD5: String
    ) async throws
}

public enum VerifyCacheUploadServiceError: FatalError, Equatable {
    case unknownError(Int)
    case notFound(String)
    case paymentRequired(String)
    case unauthorized(String)

    public var type: ErrorType {
        switch self {
        case .unknownError:
            return .bug
        case .notFound, .paymentRequired, .unauthorized:
            return .abort
        }
    }

    public var description: String {
        switch self {
        case let .unknownError(statusCode):
            return "The upload of the remote cache artifact could not be verified due to an unknown Tuist Cloud response of \(statusCode)."
        case let .notFound(message), let .paymentRequired(message), let .unauthorized(message):
            return message
        }
    }
}

public final class VerifyCacheUploadService: VerifyCacheUploadServicing {
    public init() {}

    public func verifyCacheUpload(
        serverURL: URL,
        projectId: String,
        hash: String,
        name: String,
        contentMD5: String
    ) async throws {
        let client = Client.cloud(serverURL: serverURL)
        
        let response = try await client.verifyCacheUpload(
            .init(query: .init(project_id: projectId, hash: hash, name: name, content_md5: contentMD5))
        )
        
        switch response {
        case let .ok(okResponse):
            switch okResponse.body {
            case .json:
                // noop
                break
            }
        case let .undocumented(statusCode: statusCode, _):
            throw VerifyCacheUploadServiceError.unknownError(statusCode)
        }
    }
}
