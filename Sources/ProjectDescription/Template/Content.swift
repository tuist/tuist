import Foundation

/// Content to generate in `.generated` `Template.File`
public struct Content: Codable {
    /// Generated String content
    public let content: String
    
    /// - Parameters:
    ///     - generateContent: Closure to generate content with (can throw errors that will be displayed to the user if occurs)
    public init(_ generateContent: () throws -> String) {
        do {
            self.content = try generateContent()
            dumpIfNeeded(self)
        } catch {
            if let localizedDescriptionData = "\(error)".data(using: .utf8) {
                FileHandle.standardError.write(localizedDescriptionData)
            }
            exit(1)
        }
    }
}
