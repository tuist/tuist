import Foundation
import TSCBasic

/// A type that represents a source file.
public struct SourceFile: ExpressibleByStringLiteral, Equatable {
    /// Source file path.
    public var path: AbsolutePath

    /// Compiler flags.
    public var compilerFlags: String?

    /// This is intended to be used by the mappers that generate files through side effects.
    /// This attribute is used by the content hasher used by the caching functionality.
    public var hash: String?

    public init(path: AbsolutePath,
                compilerFlags: String? = nil,
                hash: String? = nil)
    {
        self.path = path
        self.compilerFlags = compilerFlags
        self.hash = hash
    }

    // MARK: - ExpressibleByStringLiteral

    public init(stringLiteral value: String) {
        path = AbsolutePath(value)
        compilerFlags = nil
        hash = nil
    }
}
