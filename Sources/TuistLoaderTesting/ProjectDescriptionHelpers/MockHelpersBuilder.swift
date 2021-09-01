import Foundation
import TSCBasic
import TuistGraph
import TuistSupport

@testable import TuistLoader

public final class MockHelpersBuilder: HelpersBuilding {

    public var buildProjectAutomationHelpersStub: (
        AbsolutePath, ModuleSearchPaths
    ) -> [HelpersModule] = { _, _ in [] }
    public func buildProjectAutomationHelpers(
        at path: AbsolutePath,
        projectAutomationSearchPaths: ModuleSearchPaths
    ) throws -> [HelpersModule] {
        buildProjectAutomationHelpersStub(path, projectAutomationSearchPaths)
    }
    
    public var buildProjectDescriptionHelpersStub: (
        AbsolutePath, ModuleSearchPaths, [ProjectDescriptionHelpersPlugin]
    ) -> [HelpersModule] = { _, _, _ in [] }
    public func buildProjectDescriptionHelpers(
        at path: AbsolutePath,
        projectDescriptionSearchPaths: ModuleSearchPaths,
        projectDescriptionHelperPlugins: [ProjectDescriptionHelpersPlugin]
    ) throws -> [HelpersModule] {
        buildProjectDescriptionHelpersStub(path, projectDescriptionSearchPaths, projectDescriptionHelperPlugins)
    }

    public var buildPluginsStub: (
        AbsolutePath, ModuleSearchPaths, [ProjectDescriptionHelpersPlugin]
    ) -> [HelpersModule] = { _, _, _ in [] }
    public func buildPlugins(
        at path: AbsolutePath,
        projectDescriptionSearchPaths: ModuleSearchPaths,
        projectDescriptionHelperPlugins: [ProjectDescriptionHelpersPlugin]
    ) throws -> [HelpersModule] {
        buildPluginsStub(path, projectDescriptionSearchPaths, projectDescriptionHelperPlugins)
    }
}
