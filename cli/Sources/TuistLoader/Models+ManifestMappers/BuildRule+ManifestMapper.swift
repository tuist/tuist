import Foundation
import ProjectDescription
import XcodeGraph

extension XcodeGraph.BuildRule {
    static func from(manifest: ProjectDescription.BuildRule) -> Self {
        .init(
            compilerSpec: XcodeGraph.BuildRule.CompilerSpec.from(manifest: manifest.compilerSpec),
            fileType: XcodeGraph.BuildRule.FileType.from(manifest: manifest.fileType),
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
