import Path

public struct TestAttachment {
    public let filePath: AbsolutePath
    public let fileName: String

    public init(filePath: AbsolutePath, fileName: String) {
        self.filePath = filePath
        self.fileName = fileName
    }
}
