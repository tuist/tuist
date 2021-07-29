import TSCBasic

@testable import TuistDependencies

// swiftlint:disable:next type_name
public final class MockSwiftPackageManagerModuleMapGenerator: SwiftPackageManagerModuleMapGenerating {
    public init() {}

    var invokedGenerate = false
    var generateStub: (
        (String, AbsolutePath) throws -> (type: ModuleMapType, path: AbsolutePath?)
    )?

    public func generate(moduleName: String, publicHeadersPath: AbsolutePath) throws -> (type: ModuleMapType, path: AbsolutePath?) {
        invokedGenerate = true
        return try generateStub?(moduleName, publicHeadersPath) ?? (.none, nil)
    }
}
