import TSCBasic
import TSCUtility
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
    public var setToolsVersionStub: ((AbsolutePath, Version) throws -> Void)?
    public func setToolsVersion(at path: AbsolutePath, to version: Version) throws {
        invokedSetToolsVersion = true
        try setToolsVersionStub?(path, version)
    }

    public var invokedGetToolsVersion = false
    public var getToolsVersionStub: ((AbsolutePath) throws -> Version)?
    public func getToolsVersion(at path: AbsolutePath) throws -> Version {
        invokedGetToolsVersion = true
        return try getToolsVersionStub?(path) ?? Version("5.4.0")
    }

    public var invokedLoadPackageInfo = false
    public var loadPackageInfoStub: ((AbsolutePath) throws -> PackageInfo)?
    public func loadPackageInfo(at path: AbsolutePath) throws -> PackageInfo {
        invokedLoadPackageInfo = true
        return try loadPackageInfoStub?(path)
            ?? .init(
                name: "Package",
                products: [],
                dependencies: [],
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
