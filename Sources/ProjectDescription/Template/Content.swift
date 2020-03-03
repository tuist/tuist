import Foundation

/// Content to generate in `.generated` `Template.File`
public struct Content {
    /// - Parameters:
    ///     - generateContent: Closure to generate content with (can throw errors that will be displayed to the user if occurs)
    public init(_ generateContent: () throws -> String) {
        do {
            dumpIfNeeded(try generateContent())
        } catch {
            if let localizedDescriptionData = "\(error)".data(using: .utf8) {
                FileHandle.standardError.write(localizedDescriptionData)
            }
            exit(1)
        }
    }
}
