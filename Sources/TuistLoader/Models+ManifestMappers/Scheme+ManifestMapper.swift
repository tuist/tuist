import Foundation
import Path
import ProjectDescription
import TuistCore
import XcodeGraph

extension XcodeGraph.Scheme {
    /// Maps a ProjectDescription.Scheme instance into a XcodeGraph.Scheme instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of build action model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.Scheme, generatorPaths: GeneratorPaths) throws -> XcodeGraph.Scheme {
        let name = manifest.name
        let shared = manifest.shared
        let hidden = manifest.hidden
        let buildAction = try manifest.buildAction.map { try XcodeGraph.BuildAction.from(
            manifest: $0,
            generatorPaths: generatorPaths
        ) }
        let testAction = try manifest.testAction.map { try XcodeGraph.TestAction.from(
            manifest: $0,
            generatorPaths: generatorPaths
        ) }
        let runAction = try manifest.runAction.map { try XcodeGraph.RunAction.from(
            manifest: $0,
            generatorPaths: generatorPaths
        ) }
        let archiveAction = try manifest.archiveAction.map { try XcodeGraph.ArchiveAction.from(
            manifest: $0,
            generatorPaths: generatorPaths
        ) }
        let profileAction = try manifest.profileAction.map { try XcodeGraph.ProfileAction.from(
            manifest: $0,
            generatorPaths: generatorPaths
        ) }
        let analyzeAction = try manifest.analyzeAction.map { try XcodeGraph.AnalyzeAction.from(
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
