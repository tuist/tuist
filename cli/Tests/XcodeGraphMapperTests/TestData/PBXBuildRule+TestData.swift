import XcodeGraph
import XcodeProj

extension PBXBuildRule {
    static func test(
        compilerSpec: String = BuildRule.CompilerSpec.appleClang.rawValue,
        fileType: String = BuildRule.FileType.cSource.rawValue,
        isEditable: Bool = true,
        filePatterns: String? = "*.cpp;*.cxx;*.cc",
        name: String = "Default Build Rule",
        dependencyFile: String? = nil,
        outputFiles: [String] = ["$(DERIVED_FILE_DIR)/$(INPUT_FILE_BASE).o"],
        inputFiles: [String] = [],
        outputFilesCompilerFlags: [String]? = nil,
        script: String? = nil,
        runOncePerArchitecture: Bool? = nil
    ) -> PBXBuildRule {
        PBXBuildRule(
            compilerSpec: compilerSpec,
            fileType: fileType,
            isEditable: isEditable,
            filePatterns: filePatterns,
            name: name,
            dependencyFile: dependencyFile,
            outputFiles: outputFiles,
            inputFiles: inputFiles,
            outputFilesCompilerFlags: outputFilesCompilerFlags,
            script: script,
            runOncePerArchitecture: runOncePerArchitecture
        )
    }
}
