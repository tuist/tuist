import Foundation

/// A BuildRule is used to specify a method for transforming an input file in to an output file(s).
public struct BuildRule: Codable, Equatable {
    /// Compiler specification for element transformation.
    public let compilerSpec: CompilerSpec

    /// Regex pattern when `sourceFilesWithNamesMatching` is used.
    public let filePatterns: String?

    /// File types which are processed by build rule.
    public let fileType: FileType

    /// Build rule name.
    public let name: String?

    /// Build rule output files.
    public let outputFiles: [String]

    /// Build rule input files.
    public let inputFiles: [String]

    /// Build rule output files compiler flags.
    public let outputFilesCompilerFlags: [String]

    /// Build rule custom script when `customScript` is used.
    public let script: String?

    /// Build rule run once per architecture.
    public let runOncePerArchitecture: Bool?

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
