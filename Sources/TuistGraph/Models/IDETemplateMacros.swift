import Foundation

public struct IDETemplateMacros: Codable, Hashable {
    enum CodingKeys: String, CodingKey {
        case fileHeader = "FILEHEADER"
    }
    
    public let fileHeader: String?
    
    public init(fileHeader: String?) {
        self.fileHeader = fileHeader
    }
}
