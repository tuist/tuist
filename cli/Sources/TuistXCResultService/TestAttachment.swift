import Path

public struct TestAttachment {
    public let filePath: AbsolutePath
    public let fileName: String
    public let repetitionNumber: Int?

    public init(filePath: AbsolutePath, fileName: String, repetitionNumber: Int? = nil) {
        self.filePath = filePath
        self.fileName = fileName
        self.repetitionNumber = repetitionNumber
    }
}
