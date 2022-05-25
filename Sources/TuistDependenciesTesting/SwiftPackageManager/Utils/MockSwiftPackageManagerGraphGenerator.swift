import ProjectDescription
import TSCBasic
import TSCUtility
import TuistCore
import TuistGraph

@testable import TuistDependencies

public final class MockSwiftPackageManagerGraphGenerator: SwiftPackageManagerGraphGenerating {
    public init() {}

    var invokedGenerate = false
    var generateStub: (
        (
            AbsolutePath,
            [String: TuistGraph.Product],
            Set<TuistGraph.Platform>,
            TuistGraph.Settings,
            [String: TuistGraph.SettingsDictionary],
            TSCUtility.Version?,
            [String: TuistGraph.Project.Configuration]
        ) throws -> TuistCore.DependenciesGraph
    )?

    public func generate(
        at path: AbsolutePath,
        productTypes: [String: TuistGraph.Product],
        platforms: Set<TuistGraph.Platform>,
        baseSettings: TuistGraph.Settings,
        targetSettings: [String: TuistGraph.SettingsDictionary],
        swiftToolsVersion: TSCUtility.Version?,
        configurations: [String: TuistGraph.Project.Configuration]
    ) throws -> TuistCore.DependenciesGraph {
        invokedGenerate = true
        return try generateStub?(
            path,
            productTypes,
            platforms,
            baseSettings,
            targetSettings,
            swiftToolsVersion,
            configurations
        ) ?? .test()
    }
}
