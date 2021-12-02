@testable import TuistCache

public extension CloudVerifyUploadResponse {
    static func test(uploadedSize: Int = 0) -> CloudVerifyUploadResponse {
        CloudVerifyUploadResponse(uploadedSize: uploadedSize)
    }
}
