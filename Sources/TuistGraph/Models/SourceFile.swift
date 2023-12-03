import Foundation
import TSCBasic

/// A type that represents a source file.
public struct SourceFile: ExpressibleByStringLiteral, Equatable, Codable {
    /// Source file path.
    public var path: AbsolutePath

    /// Compiler flags
    /// When source files are added to a target, they can contain compiler flags that Xcode's build system
    /// passes to the compiler when compiling those files. By default none is passed.
    public var compilerFlags: String?

    /// This is intended to be used by the mappers that generate files through side effects.
    /// This attribute is used by the content hasher used by the caching functionality.
    public var contentHash: String?

    /// Source file code generation attribute
    public let codeGen: FileCodeGen?

    /// Source file condition for platform filters
    public let condition:  TargetDependency.Condition?

    public init(
        path: AbsolutePath,
        compilerFlags: String? = nil,
        contentHash: String? = nil,
        codeGen: FileCodeGen? = nil,
        condition: TargetDependency.Condition? = nil
    ) {
        self.path = path
        self.compilerFlags = compilerFlags
        self.contentHash = contentHash
        self.codeGen = codeGen
        self.condition = condition
    }

    // MARK: - ExpressibleByStringLiteral

    public init(stringLiteral value: String) {
        path = try! AbsolutePath(validating: value) // swiftlint:disable:this force_try
        compilerFlags = nil
        contentHash = nil
        codeGen = nil
        self.condition = nil
    }
}
