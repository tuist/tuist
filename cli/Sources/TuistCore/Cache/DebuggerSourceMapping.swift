import Path

/// A producer-to-consumer source mapping for a restored module, without modifying its binary or dSYM.
public struct DebuggerSourceMapping: Hashable, Sendable {
    public let original: AbsolutePath
    public let current: AbsolutePath

    public init(original: AbsolutePath, current: AbsolutePath) {
        self.original = original
        self.current = current
    }
}
