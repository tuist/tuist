import Foundation

/// A type that represents a list of source files defined by a glob.
public struct SourceFileGlob: Equatable {
    /// Glob pattern to unfold all the source files.
    public let glob: String

    /// Glob pattern used for filtering out files.
    public let excluding: [String]

    /// Compiler flags.
    public let compilerFlags: String?

    /// Source file code generation attribute.
    public let codeGen: FileCodeGen?

    /// Compilation condition the source file.
    public let compilationCondition: PlatformCondition?

    /// Initializes the source file glob.
    /// - Parameters:
    ///   - glob: Glob pattern to unfold all the source files.
    ///   - excluding: Glob pattern used for filtering out files.
    ///   - compilerFlags: Compiler flags.
    ///   - codeGen: Source file code generation attribute.
    ///   - compilationCondition: Condition for file compilation.
    public init(
        glob: String,
        excluding: [String] = [],
        compilerFlags: String? = nil,
        codeGen: FileCodeGen? = nil,
        compilationCondition: PlatformCondition? = nil
    ) {
        self.glob = glob
        self.excluding = excluding
        self.compilerFlags = compilerFlags
        self.codeGen = codeGen
        self.compilationCondition = compilationCondition
    }
}
