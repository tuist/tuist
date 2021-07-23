import TSCBasic

@testable import TuistDependencies

public final class MockSwiftPackageManagerModuleMapGenerator: SwiftPackageManagerModuleMapGenerating {
    public init() {}

    var invokedGenerate = false
    var generateStub: (
        (String, AbsolutePath) throws -> AbsolutePath?
    )?

    public func generate(moduleName: String, publicHeadersPath: AbsolutePath) throws -> AbsolutePath? {
        invokedGenerate = true
        return try generateStub?(moduleName, publicHeadersPath) ?? nil
    }
}
