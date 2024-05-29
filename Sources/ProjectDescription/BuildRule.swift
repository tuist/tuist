import Foundation

/// A BuildRule is used to specify a method for transforming an input file in to an output file(s).
public struct BuildRule: Codable, Equatable, Sendable {
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

    public static func buildRule(
        name: String? = nil,
        fileType: FileType,
        filePatterns: String? = nil,
        compilerSpec: CompilerSpec,
        inputFiles: [String] = [],
        outputFiles: [String] = [],
        outputFilesCompilerFlags: [String] = [],
        script: String? = nil,
        runOncePerArchitecture: Bool = false
    ) -> Self {
        self.init(
            compilerSpec: compilerSpec,
            filePatterns: filePatterns,
            fileType: fileType,
            name: name,
            outputFiles: outputFiles,
            inputFiles: inputFiles,
            outputFilesCompilerFlags: outputFilesCompilerFlags,
            script: script,
            runOncePerArchitecture: runOncePerArchitecture
        )
    }
}
