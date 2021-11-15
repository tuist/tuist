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
            [String: TuistGraph.SettingsDictionary],
            TSCUtility.Version?
        ) throws -> TuistCore.DependenciesGraph
    )?

    public func generate(
        at path: AbsolutePath,
        productTypes: [String: TuistGraph.Product],
        platforms: Set<TuistGraph.Platform>,
        targetSettings: [String : TuistGraph.SettingsDictionary],
        swiftToolsVersion: TSCUtility.Version?
    ) throws -> TuistCore.DependenciesGraph {
        invokedGenerate = true
        return try generateStub?(path, productTypes, platforms, targetSettings, swiftToolsVersion) ?? .test()
    }
}
