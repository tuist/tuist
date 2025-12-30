import Foundation

public struct AppBuildUpload {
    public let appBuildId: String
    public let uploadId: String

    public init(
        appBuildId: String,
        uploadId: String
    ) {
        self.appBuildId = appBuildId
        self.uploadId = uploadId
    }
}
