import Path

public struct TestAttachment {
    public let filePath: AbsolutePath
    public let fileName: String
    public let repetitionNumber: Int?
    public let argumentName: String?

    public init(filePath: AbsolutePath, fileName: String, repetitionNumber: Int? = nil, argumentName: String? = nil) {
        self.filePath = filePath
        self.fileName = fileName
        self.repetitionNumber = repetitionNumber
        self.argumentName = argumentName
    }
}
