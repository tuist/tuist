import Foundation

public struct IDETemplateMacros: Codable, Hashable {
    enum CodingKeys: String, CodingKey {
        case fileHeader = "FILEHEADER"
    }

    public let fileHeader: String?

    public init(fileHeader: String?) {
        // Xcode by default adds extra newline at the end, so if it is present, just remove it
        if var fileHeader = fileHeader, fileHeader.last == "\n" {
            fileHeader.removeLast()
            self.fileHeader = fileHeader
        } else {
            self.fileHeader = fileHeader
        }
    }
}
