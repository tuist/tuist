import Path

public struct TestAttachment: Encodable, Sendable {
    public let filePath: AbsolutePath
    public let fileName: String
    public let repetitionNumber: Int?

    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
        case fileName = "file_name"
        case repetitionNumber = "repetition_number"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(filePath.pathString, forKey: .filePath)
        try container.encode(fileName, forKey: .fileName)
        try container.encodeIfPresent(repetitionNumber, forKey: .repetitionNumber)
    }

    public init(filePath: AbsolutePath, fileName: String, repetitionNumber: Int? = nil) {
        self.filePath = filePath
        self.fileName = fileName
        self.repetitionNumber = repetitionNumber
    }
}
