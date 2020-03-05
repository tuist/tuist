import Foundation

/// It represents an output from the xcodebuild command.
public struct XcodeBuildOutput: Equatable {
    /// Output as xcodebuild returns it.
    let raw: String

    /// Beautified version of the raw output.
    let formatted: String?

    /// Initializes the output with its arguments.
    /// - Parameters:
    ///   - raw: Output as xcodebuild returns it.
    ///   - formatted: Beautified version of the raw output.
    public init(raw: String, formatted: String?) {
        self.raw = raw
        self.formatted = formatted
    }
}
