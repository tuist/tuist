import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistSupport

extension TuistCore.Scheme {
    /// Maps a ProjectDescription.Scheme instance into a TuistCore.Scheme instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of build action model.
    ///   - pathResolver: A path resolver.
    static func from(manifest: ProjectDescription.Scheme, generatorPaths: GeneratorPaths) throws -> TuistCore.Scheme {
        let name = manifest.name
        let shared = manifest.shared
        let buildAction = try manifest.buildAction.map { try TuistCore.BuildAction.from(manifest: $0,
                                                                                        generatorPaths: generatorPaths) }
        let testAction = try manifest.testAction.map { try TuistCore.TestAction.from(manifest: $0,
                                                                                     generatorPaths: generatorPaths) }
        let runAction = try manifest.runAction.map { try TuistCore.RunAction.from(manifest: $0,
                                                                                  generatorPaths: generatorPaths) }
        let archiveAction = try manifest.archiveAction.map { try TuistCore.ArchiveAction.from(manifest: $0,
                                                                                              generatorPaths: generatorPaths) }
        let profileAction = try manifest.profileAction.map { try TuistCore.ProfileAction.from(manifest: $0,
                                                                                              generatorPaths: generatorPaths) }
        let analyzeAction = try manifest.analyzeAction.map { try TuistCore.AnalyzeAction.from(manifest: $0,
                                                                                              generatorPaths: generatorPaths) }

        return Scheme(name: name,
                      shared: shared,
                      buildAction: buildAction,
                      testAction: testAction,
                      runAction: runAction,
                      archiveAction: archiveAction,
                      profileAction: profileAction,
                      analyzeAction: analyzeAction)
    }
}
