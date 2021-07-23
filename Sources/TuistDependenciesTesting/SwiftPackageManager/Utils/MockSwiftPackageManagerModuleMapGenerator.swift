import TSCBasic

@testable import TuistDependencies

// swiftlint:disable:next type_name
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
