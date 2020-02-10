import Basic
import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.Scheme {
    static func from(manifest: ProjectDescription.Scheme, projectPath: AbsolutePath, generatorPaths: GeneratorPaths) throws -> TuistCore.Scheme {
        let name = manifest.name
        let shared = manifest.shared
        let buildAction = try manifest.buildAction.map { try TuistCore.BuildAction.from(manifest: $0,
                                                                                        projectPath: projectPath,
                                                                                        generatorPaths: generatorPaths) }
        let testAction = try manifest.testAction.map { try TuistCore.TestAction.from(manifest: $0,
                                                                                     projectPath: projectPath,
                                                                                     generatorPaths: generatorPaths) }
        let runAction = try manifest.runAction.map { try TuistCore.RunAction.from(manifest: $0,
                                                                                  generatorPaths: generatorPaths) }
        let archiveAction = try manifest.archiveAction.map { try TuistCore.ArchiveAction.from(manifest: $0,
                                                                                              projectPath: projectPath,
                                                                                              generatorPaths: generatorPaths) }

        return Scheme(name: name,
                      shared: shared,
                      buildAction: buildAction,
                      testAction: testAction,
                      runAction: runAction,
                      archiveAction: archiveAction)
    }

    static func from(manifest: ProjectDescription.Scheme, workspacePath: AbsolutePath, generatorPaths: GeneratorPaths) throws -> TuistCore.Scheme {
        let name = manifest.name
        let shared = manifest.shared
        let buildAction = try manifest.buildAction.map { try TuistCore.BuildAction.from(manifest: $0,
                                                                                        projectPath: workspacePath,
                                                                                        generatorPaths: generatorPaths) }
        let testAction = try manifest.testAction.map { try TuistCore.TestAction.from(manifest: $0,
                                                                                     projectPath: workspacePath,
                                                                                     generatorPaths: generatorPaths) }
        let runAction = try manifest.runAction.map { try TuistCore.RunAction.from(manifest: $0,
                                                                                  generatorPaths: generatorPaths) }
        let archiveAction = try manifest.archiveAction.map { try TuistCore.ArchiveAction.from(manifest: $0,
                                                                                              projectPath: workspacePath,
                                                                                              generatorPaths: generatorPaths) }

        return Scheme(name: name,
                      shared: shared,
                      buildAction: buildAction,
                      testAction: testAction,
                      runAction: runAction,
                      archiveAction: archiveAction)
    }
}
