import Foundation
import TSCBasic
import TSCUtility
@testable import TuistGraph

extension Workspace {
    public static func test(
        path: AbsolutePath = AbsolutePath("/"),
        xcWorkspacePath: AbsolutePath = AbsolutePath("/"),
        name: String = "test",
        projects: [AbsolutePath] = [],
        schemes: [Scheme] = [],
        ideTemplateMacros: IDETemplateMacros? = nil,
        additionalFiles: [FileElement] = [],
        lastUpgradeCheck: Version? = nil,
        generationOptions: GenerationOptions? = nil
    ) -> Workspace {
        Workspace(
            path: path,
            xcWorkspacePath: xcWorkspacePath,
            name: name,
            projects: projects,
            schemes: schemes,
            generationOptions: generationOptions,
            ideTemplateMacros: ideTemplateMacros,
            additionalFiles: additionalFiles,
            lastUpgradeCheck: lastUpgradeCheck
        )
    }
}
