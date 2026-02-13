import Foundation
import XcodeGraph
import XcodeProj

protocol BuildRulesGenerating {
    func generateBuildRules(target: Target, pbxTarget: PBXTarget, pbxproj: PBXProj) throws
}

struct BuildRulesGenerator: BuildRulesGenerating {
    func generateBuildRules(target: Target, pbxTarget: PBXTarget, pbxproj: PBXProj) throws {
        for buildRule in target.buildRules {
            let rule = PBXBuildRule(
                compilerSpec: buildRule.compilerSpec.rawValue,
                fileType: buildRule.fileType.rawValue,
                isEditable: true,
                filePatterns: buildRule.filePatterns,
                name: buildRule.name,
                outputFiles: buildRule.outputFiles,
                inputFiles: buildRule.inputFiles,
                outputFilesCompilerFlags: buildRule.outputFilesCompilerFlags,
                script: buildRule.script,
                runOncePerArchitecture: buildRule.runOncePerArchitecture
            )
            pbxTarget.buildRules.append(rule)
            pbxproj.add(object: rule)
        }
    }
}
