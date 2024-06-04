import Foundation

/// A BuildRule is used to specify a method for transforming an input file in to an output file(s).
public struct BuildRule: Codable, Equatable {
    /// Element compiler spec.
    public let compilerSpec: CompilerSpec

    /// Element file patterns.
    public let filePatterns: String?

    /// Element file type.
    public let fileType: FileType

    /// Element name.
    public let name: String?

    /// Element output files.
    public let outputFiles: [String]

    /// Element input files.
    public let inputFiles: [String]?

    /// Element output files compiler flags.
    public let outputFilesCompilerFlags: [String]?

    /// Element script.
    public let script: String?

    /// Element run once per architecture.
    public let runOncePerArchitecture: Bool?

    public init(
        compilerSpec: CompilerSpec,
        fileType: FileType,
        filePatterns: String? = nil,
        name: String? = nil,
        outputFiles: [String] = [],
        inputFiles: [String]? = nil,
        outputFilesCompilerFlags: [String]? = nil,
        script: String? = nil,
        runOncePerArchitecture: Bool? = nil
    ) {
        self.compilerSpec = compilerSpec
        self.filePatterns = filePatterns
        self.fileType = fileType
        self.name = name
        self.outputFiles = outputFiles
        self.inputFiles = inputFiles
        self.outputFilesCompilerFlags = outputFilesCompilerFlags
        self.script = script
        self.runOncePerArchitecture = runOncePerArchitecture
    }
}
