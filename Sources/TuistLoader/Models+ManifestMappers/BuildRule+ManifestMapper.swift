import Foundation
import ProjectDescription
import TuistGraph

extension TuistGraph.BuildRule {
    static func from(manifest: ProjectDescription.BuildRule) -> Self {
        .init(
            compilerSpec: TuistGraph.BuildRule.CompilerSpec.from(manifest: manifest.compilerSpec),
            fileType: TuistGraph.BuildRule.FileType.from(manifest: manifest.fileType),
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
