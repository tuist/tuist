import Foundation

public struct IDETemplateMacros: Codable, Hashable {
    private enum CodingKeys: String, CodingKey {
        case fileHeader = "FILEHEADER"
    }

    public let fileHeader: String?

    public init(fileHeader: String?) {
        self.fileHeader = fileHeader.map(Self.normalize)
    }

    private static func normalize(fileHeader: String) -> String {
        var fileHeader = fileHeader

        // As Xcode appends file header directly after `//` it adds to the beginning of template,
        // it is desired to also add leading space if it is not already present,
        // but if header starts with `//` then I know what I am doing and it should be kept intact
        if !fileHeader.hasPrefix("//"), let first = fileHeader.first.map(String.init),
           first.trimmingCharacters(in: .whitespacesAndNewlines) == first
        {
            fileHeader.insert(" ", at: fileHeader.startIndex)
        }

        // Xcode by default adds comment slashes to first line of header template
        if fileHeader.hasPrefix("//") {
            fileHeader.removeFirst(2)
        }

        // Xcode by default adds extra newline at the end, so if it is present, just remove it
        if fileHeader.last == "\n" {
            fileHeader.removeLast()
        }

        return fileHeader
    }
}
