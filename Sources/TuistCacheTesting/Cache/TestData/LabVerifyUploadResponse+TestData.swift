@testable import TuistCache

extension LabVerifyUploadResponse {
    public static func test(uploadedSize: Int = 0) -> LabVerifyUploadResponse {
        LabVerifyUploadResponse(uploadedSize: uploadedSize)
    }
}
