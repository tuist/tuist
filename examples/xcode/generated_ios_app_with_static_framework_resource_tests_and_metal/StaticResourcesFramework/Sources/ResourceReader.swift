import Foundation

public final class ResourceReader {
    public init() {}

    public func message() throws -> String {
        guard let url = Bundle.module.url(forResource: "Message", withExtension: "txt") else {
            throw ResourceReaderError.missingBundleResource
        }
        return try String(contentsOf: url).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum ResourceReaderError: Error {
    case missingBundleResource
}
