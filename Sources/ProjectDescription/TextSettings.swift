import Foundation

/// Text settings for Xcode project
public struct TextSettings: Codable, Equatable {
    /// Use tabs over spaces
    public let usesTabs: Bool?
    /// Indent width
    public let indentWidth: UInt?
    /// Tab width
    public let tabWidth: UInt?
    /// Wrap lines
    public let wrapsLines: Bool?
    
    /// Create new `TextSettings` instance.
    ///
    /// - Parameters:
    ///   - usesTabs: Use tabs over spaces.
    ///   - indentWidth: Indent width.
    ///   - tabWidth: Tab width.
    ///   - wrapsLines: Wrap lines.
    public static func textSettings(
        usesTabs: Bool? = nil,
        indentWidth: UInt? = nil,
        tabWidth: UInt? = nil,
        wrapsLines: Bool? = nil
    ) -> TextSettings {
        TextSettings(
            usesTabs: usesTabs,
            indentWidth: indentWidth,
            tabWidth: tabWidth,
            wrapsLines: wrapsLines
        )
    }
    
    private init(
        usesTabs: Bool? = nil,
        indentWidth: UInt? = nil,
        tabWidth: UInt? = nil,
        wrapsLines: Bool? = nil
    ) {
        self.usesTabs = usesTabs
        self.indentWidth = indentWidth
        self.tabWidth = tabWidth
        self.wrapsLines = wrapsLines
    }
}
