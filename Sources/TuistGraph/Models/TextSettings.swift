import Foundation

/// Text settings for Xcode project
public struct TextSettings: Codable {
    /// Use tabs over spaces
    public let usesTabs: Bool?
    /// Indent width
    public let indentWidth: UInt?
    /// Tab width
    public let tabWidth: UInt?
    /// Wrap lines
    public let wrapsLines: Bool?

    public init(
        usesTabs: Bool?,
        indentWidth: UInt?,
        tabWidth: UInt?,
        wrapsLines: Bool?
    ) {
        self.usesTabs = usesTabs
        self.indentWidth = indentWidth
        self.tabWidth = tabWidth
        self.wrapsLines = wrapsLines
    }
}
