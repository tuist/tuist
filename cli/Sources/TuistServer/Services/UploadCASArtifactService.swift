import Foundation
import Mockable
import OpenAPIURLSession
import OpenAPIRuntime

@Mockable
public protocol UploadCASArtifactServicing {
    func uploadCASArtifact(
        _ data: Data,
        casId: String,
        fullHandle: String,
        serverURL: URL
    ) async throws
}

enum UploadCASArtifactServiceError: LocalizedError {
    case unknownError(Int)
    case unauthorized(String)
    case forbidden(String)
    case notFound(String)
    case uploadFailed

    var errorDescription: String? {
        switch self {
        case let .unknownError(statusCode):
            return "The CAS artifact could not be uploaded due to an unknown Tuist response of \(statusCode)."
        case let .unauthorized(message), let .forbidden(message), let .notFound(message):
            return message
        case .uploadFailed:
            return "The CAS artifact upload failed due to an unknown error."
        }
    }
}

public final class UploadCASArtifactService: UploadCASArtifactServicing {
    private let fullHandleService: FullHandleServicing

    public convenience init() {
        self.init(
            fullHandleService: FullHandleService()
        )
    }

    init(
        fullHandleService: FullHandleServicing
    ) {
        self.fullHandleService = fullHandleService
    }

    public func uploadCASArtifact(
        _ data: Data,
        casId: String,
        fullHandle: String,
        serverURL: URL
    ) async throws {
        print("🔄 UploadCASArtifactService starting upload:")
        print("  - CAS ID: \(casId)")
        print("  - Data size: \(data.count) bytes")
        print("  - Server URL: \(serverURL)")
        print("  - Full handle: \(fullHandle)")
        
        // Log data characteristics
        print("  - Data first 32 bytes: \(data.prefix(32).map { String(format: "%02x", $0) }.joined())")
        print("  - Data last 32 bytes: \(data.suffix(32).map { String(format: "%02x", $0) }.joined())")
        print("  - CAS ID length: \(casId.count)")
        print("  - CAS ID contains '=': \(casId.contains("="))")
        print("  - CAS ID contains URL-unsafe chars: \(casId.contains { !$0.isASCII || "/?#[]@!$&'()*+,;= ".contains($0) })")
        
        let client = Client.authenticated(serverURL: serverURL)
        let handles = try fullHandleService.parse(fullHandle)

        print("  - Account handle: \(handles.accountHandle)")
        print("  - Project handle: \(handles.projectHandle)")
        
        print("🚀 Making upload request...")
        let response = try! await client.uploadCASArtifact(
            .init(
                path: .init(id: casId),
                query: .init(
                    account_handle: handles.accountHandle,
                    project_handle: handles.projectHandle
                ),
                body: .binary(HTTPBody(data))
            )
        )
        print("✅ Upload request completed successfully")

        switch response {
        case .ok:
            // Upload successful
            print("✅ Upload successful (200 OK)")
            return
        case .notModified:
            // Artifact already exists, no upload needed
            print("✅ Upload not needed - artifact exists (304 Not Modified)")
            return
        case let .forbidden(forbidden):
            print("❌ Upload forbidden (403)")
            switch forbidden.body {
            case let .json(error):
                print("  - Error message: \(error.message)")
                throw UploadCASArtifactServiceError.forbidden(error.message)
            }
        case let .unauthorized(unauthorized):
            print("❌ Upload unauthorized (401)")
            switch unauthorized.body {
            case let .json(error):
                print("  - Error message: \(error.message)")
                throw UploadCASArtifactServiceError.unauthorized(error.message)
            }
        case let .undocumented(statusCode: statusCode, payload):
            print("❌ Upload failed with undocumented status code: \(statusCode)")
            print("  - Payload: \(payload)")
            throw UploadCASArtifactServiceError.unknownError(statusCode)
        }
    }
}
