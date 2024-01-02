import Foundation

/// A BuildRule is used to specify a method for transforming an input file in to an output file(s).
public struct BuildRule: Codable, Equatable {
    /// Compiler specification for element transformation.
    public var compilerSpec: CompilerSpec

    /// Regex pattern when `sourceFilesWithNamesMatching` is used.
    public var filePatterns: String?

    /// File types which are processed by build rule.
    public var fileType: FileType

    /// Build rule name.
    public var name: String?

    /// Build rule output files.
    public var outputFiles: [String]

    /// Build rule input files.
    public var inputFiles: [String]

    /// Build rule output files compiler flags.
    public var outputFilesCompilerFlags: [String]

    /// Build rule custom script when `customScript` is used.
    public var script: String?

    /// Build rule run once per architecture.
    public var runOncePerArchitecture: Bool?

    public init(
        name: String? = nil,
        fileType: FileType,
        filePatterns: String? = nil,
        compilerSpec: CompilerSpec,
        inputFiles: [String] = [],
        outputFiles: [String] = [],
        outputFilesCompilerFlags: [String] = [],
        script: String? = nil,
        runOncePerArchitecture: Bool = false
    ) {
        self.name = name
        self.fileType = fileType
        self.filePatterns = filePatterns
        self.compilerSpec = compilerSpec
        self.inputFiles = inputFiles
        self.outputFiles = outputFiles
        self.outputFilesCompilerFlags = outputFilesCompilerFlags
        self.script = script
        self.runOncePerArchitecture = runOncePerArchitecture
    }
}
