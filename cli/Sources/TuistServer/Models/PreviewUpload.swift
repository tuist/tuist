import Foundation

public struct PreviewUpload {
    public let previewId: String
    public let uploadId: String

    public init(
        previewId: String,
        uploadId: String
    ) {
        self.previewId = previewId
        self.uploadId = uploadId
    }
}
