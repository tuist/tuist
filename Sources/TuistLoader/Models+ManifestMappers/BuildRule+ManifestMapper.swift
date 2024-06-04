import Foundation
import ProjectDescription
import XcodeProjectGenerator

extension XcodeProjectGenerator.BuildRule {
    static func from(manifest: ProjectDescription.BuildRule) -> Self {
        .init(
            compilerSpec: XcodeProjectGenerator.BuildRule.CompilerSpec.from(manifest: manifest.compilerSpec),
            fileType: XcodeProjectGenerator.BuildRule.FileType.from(manifest: manifest.fileType),
            filePatterns: manifest.filePatterns,
            name: manifest.name,
            outputFiles: manifest.outputFiles,
            inputFiles: manifest.inputFiles,
            outputFilesCompilerFlags: manifest.outputFilesCompilerFlags,
            script: manifest.script,
            runOncePerArchitecture: manifest.runOncePerArchitecture
        )
    }
}
