@testable import TuistCache

extension CloudVerifyUploadResponse {
    public static func test(uploadedSize: Int = 0) -> CloudVerifyUploadResponse {
        CloudVerifyUploadResponse(uploadedSize: uploadedSize)
    }
}
