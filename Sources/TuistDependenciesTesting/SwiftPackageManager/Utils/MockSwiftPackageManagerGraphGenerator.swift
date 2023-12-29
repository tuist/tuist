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
            TuistGraph.Settings,
            [String: TuistGraph.SettingsDictionary],
            TSCUtility.Version?,
            [String: TuistGraph.Project.Options]
        ) throws -> TuistCore.DependenciesGraph
    )?

    public func generate(
        at path: AbsolutePath,
        productTypes: [String: TuistGraph.Product],
        baseSettings: TuistGraph.Settings,
        targetSettings: [String: TuistGraph.SettingsDictionary],
        swiftToolsVersion: TSCUtility.Version?,
        projectOptions: [String: TuistGraph.Project.Options]
    ) throws -> TuistCore.DependenciesGraph {
        invokedGenerate = true
        return try generateStub?(
            path,
            productTypes,
            baseSettings,
            targetSettings,
            swiftToolsVersion,
            projectOptions
        ) ?? .test()
    }
}
