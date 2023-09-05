import Foundation
import TuistCloud

public final class MockVerifyCacheUploadService: VerifyCacheUploadServicing {    
    public init() {}

    // swiftlint:disable:next large_tuple
    public var verifyCacheUploadStub: ((URL, String, String, String, String) async throws -> Void)?
    public func verifyCacheUpload(
        serverURL: URL,
        projectId: String,
        hash: String,
        name: String,
        contentMD5: String
    ) async throws {
        try await verifyCacheUploadStub?(
            serverURL,
            projectId,
            hash,
            name,
            contentMD5
        )
    }
}
