import Foundation

/// Additional options related to the `Project`
public enum ProjectOption: Codable, Equatable {
    /// Text settings to override user ones for current project
    ///
    /// - Parameters:
    ///   - usesTabs: Use tabs over spaces.
    ///   - indentWidth: Indent width.
    ///   - tabWidth: Tab width.
    ///   - wrapsLines: Wrap lines.
    case textSettings(
        usesTabs: Bool? = nil,
        indentWidth: UInt? = nil,
        tabWidth: UInt? = nil,
        wrapsLines: Bool? = nil
    )
}
