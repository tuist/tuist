import Foundation
import TuistGraph
import XcodeProj

protocol BuildRulesGenerating: AnyObject {
    func generateBuildRules(target: Target, pbxTarget: PBXTarget, pbxproj: PBXProj) throws
}

final class BuildRulesGenerator: BuildRulesGenerating {
    func generateBuildRules(target: Target, pbxTarget: PBXTarget, pbxproj: PBXProj) throws {
        target.buildRules.forEach {
            let rule = PBXBuildRule(
                compilerSpec: $0.compilerSpec.rawValue,
                fileType: $0.fileType.rawValue,
                isEditable: true,
                filePatterns: $0.filePatterns,
                name: $0.name,
                outputFiles: $0.outputFiles,
                inputFiles: $0.inputFiles,
                outputFilesCompilerFlags: $0.outputFilesCompilerFlags,
                script: $0.script,
                runOncePerArchitecture: $0.runOncePerArchitecture
            )
            pbxTarget.buildRules.append(rule)
            pbxproj.add(object: rule)
        }
    }
}
