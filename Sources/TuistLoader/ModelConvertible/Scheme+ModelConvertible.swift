import Basic
import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.Scheme: ModelConvertible {
    init(manifest: ProjectDescription.Scheme, generatorPaths: GeneratorPaths) throws {
        let name = manifest.name
        let shared = manifest.shared
        let buildAction = try manifest.buildAction.map { try TuistCore.BuildAction(manifest: $0, generatorPaths: generatorPaths) }
        let testAction = try manifest.testAction.map { try TuistCore.TestAction(manifest: $0, generatorPaths: generatorPaths) }
        let runAction = try manifest.runAction.map { try TuistCore.RunAction(manifest: $0, generatorPaths: generatorPaths) }
        let archiveAction = try manifest.archiveAction.map { try TuistCore.ArchiveAction(manifest: $0, generatorPaths: generatorPaths) }

        self.init(name: name,
                  shared: shared,
                  buildAction: buildAction,
                  testAction: testAction,
                  runAction: runAction,
                  archiveAction: archiveAction)
    }
}
