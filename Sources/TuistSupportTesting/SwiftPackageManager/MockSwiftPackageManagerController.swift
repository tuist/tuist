import TSCBasic
@testable import TuistSupport

public final class MockSwiftPackageManagerController: SwiftPackageManagerControlling {
    public init() {}

    public var invokedResolve = false
    public var resolveStub: ((AbsolutePath, Bool) throws -> Void)?
    public func resolve(at path: AbsolutePath, printOutput: Bool) throws {
        invokedResolve = true
        try resolveStub?(path, printOutput)
    }

    public var invokedUpdate = false
    public var updateStub: ((AbsolutePath, Bool) throws -> Void)?
    public func update(at path: AbsolutePath, printOutput: Bool) throws {
        invokedUpdate = true
        try updateStub?(path, printOutput)
    }

    public var invokedSetToolsVersion = false
    public var setToolsVersionStub: ((AbsolutePath, String?) throws -> Void)?
    public func setToolsVersion(at path: AbsolutePath, to version: String?) throws {
        invokedSetToolsVersion = true
        try setToolsVersionStub?(path, version)
    }

    public var invokedLoadPackageInfo = false
    public var loadPackageInfoStub: ((AbsolutePath) throws -> PackageInfo)?
    public func loadPackageInfo(at path: AbsolutePath) throws -> PackageInfo {
        invokedLoadPackageInfo = true
        return try loadPackageInfoStub?(path)
            ?? .init(
                products: [],
                targets: [],
                platforms: [],
                cLanguageStandard: nil,
                cxxLanguageStandard: nil,
                swiftLanguageVersions: nil
            )
    }

    public var invokedBuildFatReleaseBinary = false
    public var loadBuildFatReleaseBinaryStub: ((AbsolutePath, String, AbsolutePath, AbsolutePath) throws -> Void)?
    public func buildFatReleaseBinary(
        packagePath: AbsolutePath,
        product: String,
        buildPath: AbsolutePath,
        outputPath: AbsolutePath
    ) throws {
        invokedBuildFatReleaseBinary = true
        try loadBuildFatReleaseBinaryStub?(
            packagePath,
            product,
            buildPath,
            outputPath
        )
    }
}
