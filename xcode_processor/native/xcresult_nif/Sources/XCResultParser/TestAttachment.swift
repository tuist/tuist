import Foundation

public struct TestAttachment: Encodable, Sendable {
    public let filePath: String
    public let fileName: String
    public let repetitionNumber: Int?

    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
        case fileName = "file_name"
        case repetitionNumber = "repetition_number"
    }

    public init(filePath: String, fileName: String, repetitionNumber: Int? = nil) {
        self.filePath = filePath
        self.fileName = fileName
        self.repetitionNumber = repetitionNumber
    }
}
