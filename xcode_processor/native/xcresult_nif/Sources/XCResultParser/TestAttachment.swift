import Path

public struct TestAttachment: Encodable, Sendable {
    public let filePath: AbsolutePath
    public let fileName: String
    public let repetitionNumber: Int?
    public let argumentName: String?

    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
        case fileName = "file_name"
        case repetitionNumber = "repetition_number"
        case argumentName = "argument_name"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(filePath.pathString, forKey: .filePath)
        try container.encode(fileName, forKey: .fileName)
        try container.encodeIfPresent(repetitionNumber, forKey: .repetitionNumber)
        try container.encodeIfPresent(argumentName, forKey: .argumentName)
    }

    public init(filePath: AbsolutePath, fileName: String, repetitionNumber: Int? = nil, argumentName: String? = nil) {
        self.filePath = filePath
        self.fileName = fileName
        self.repetitionNumber = repetitionNumber
        self.argumentName = argumentName
    }
}
