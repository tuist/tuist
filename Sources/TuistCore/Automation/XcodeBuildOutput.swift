import Foundation

/// It represents an output from the xcodebuild command.
public struct XcodeBuildOutput: Equatable {
    /// Output as xcodebuild returns it.
    let raw: String

    /// Initializes the output with its arguments.
    /// - Parameters:
    ///   - raw: Output as xcodebuild returns it.
    public init(raw: String) {
        self.raw = raw
    }
}
