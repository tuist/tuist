import Foundation
import ProjectDescription
import TuistCore
import XcodeGraph

extension XcodeGraph.Scheme {
    /// Maps a ProjectDescription.Scheme instance into a XcodeGraph.Scheme instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of build action model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.Scheme, generatorPaths: GeneratorPaths) async throws -> XcodeGraph.Scheme {
        let name = manifest.name
        let shared = manifest.shared
        let hidden = manifest.hidden
        let buildAction = try manifest.buildAction.map { try XcodeGraph.BuildAction.from(
            manifest: $0,
            generatorPaths: generatorPaths
        ) }
        let testAction: XcodeGraph.TestAction?
        if let manifestTestAction = manifest.testAction {
            testAction = try await XcodeGraph.TestAction.from(
                manifest: manifestTestAction,
                generatorPaths: generatorPaths
            )
        } else {
            testAction = nil
        }
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
