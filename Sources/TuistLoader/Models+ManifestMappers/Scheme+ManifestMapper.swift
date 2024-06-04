import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import XcodeProjectGenerator

extension XcodeProjectGenerator.Scheme {
    /// Maps a ProjectDescription.Scheme instance into a XcodeProjectGenerator.Scheme instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of build action model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.Scheme, generatorPaths: GeneratorPaths) throws -> XcodeProjectGenerator.Scheme {
        let name = manifest.name
        let shared = manifest.shared
        let hidden = manifest.hidden
        let buildAction = try manifest.buildAction.map { try XcodeProjectGenerator.BuildAction.from(
            manifest: $0,
            generatorPaths: generatorPaths
        ) }
        let testAction = try manifest.testAction.map { try XcodeProjectGenerator.TestAction.from(
            manifest: $0,
            generatorPaths: generatorPaths
        ) }
        let runAction = try manifest.runAction.map { try XcodeProjectGenerator.RunAction.from(
            manifest: $0,
            generatorPaths: generatorPaths
        ) }
        let archiveAction = try manifest.archiveAction.map { try XcodeProjectGenerator.ArchiveAction.from(
            manifest: $0,
            generatorPaths: generatorPaths
        ) }
        let profileAction = try manifest.profileAction.map { try XcodeProjectGenerator.ProfileAction.from(
            manifest: $0,
            generatorPaths: generatorPaths
        ) }
        let analyzeAction = try manifest.analyzeAction.map { try XcodeProjectGenerator.AnalyzeAction.from(
            manifest: $0,
            generatorPaths: generatorPaths
        ) }

        return Scheme(
            name: name,
            shared: shared,
            hidden: hidden,
            buildAction: buildAction,
            testAction: testAction,
            runAction: runAction,
            archiveAction: archiveAction,
            profileAction: profileAction,
            analyzeAction: analyzeAction
        )
    }
}
