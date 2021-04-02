import TSCBasic
import TuistGraph

@testable import TuistDependencies

public final class MockSwiftPackageManager: SwiftPackageManaging {
    public init() {}
    
    var invokedResolve = false
    var invokedResolveCount = 0
    var invokedResolveParameters: AbsolutePath?
    var invokedResolveParametersList = [AbsolutePath]()
    var resolveStub: ((AbsolutePath) throws  -> Void)?
    
    public func resolve(at path: AbsolutePath) throws {
        invokedResolve = true
        invokedResolveCount += 1
        invokedResolveParameters = path
        invokedResolveParametersList.append(path)
        try resolveStub?(path)
    }
    
    var invokedGenerateXcodeProject = false
    var invokedGenerateXcodeProjectCount = 0
    var invokedGenerateXcodeProjectParameters: (AbsolutePath, AbsolutePath)?
    var invokedGenerateXcodeProjectParametersList = [(AbsolutePath, AbsolutePath)]() // swiftlint:disable:this identifier_name
    var generateXcodeProjectStub: ((AbsolutePath, AbsolutePath) throws  -> Void)?
    
    public func generateXcodeProject(at path: AbsolutePath, outputPath: AbsolutePath) throws {
        invokedGenerateXcodeProject = true
        invokedGenerateXcodeProjectCount += 1
        invokedGenerateXcodeProjectParameters = (path, outputPath)
        invokedGenerateXcodeProjectParametersList.append((path, outputPath))
        try generateXcodeProjectStub?(path, outputPath)
    }
    
    var invokedLoadDependencies = false
    var invokedLoadDependenciesCount = 0
    var invokedLoadDependenciesParameters: AbsolutePath?
    var invokedLoadDependenciesParametersList = [AbsolutePath]()
    var loadDependenciesStub: ((AbsolutePath) throws  -> PackageDependency)?
    
    public func loadDependencies(at path: AbsolutePath) throws -> PackageDependency {
        invokedLoadDependencies = true
        invokedLoadDependenciesCount += 1
        invokedLoadDependenciesParameters = path
        invokedLoadDependenciesParametersList.append(path)
        return (try loadDependenciesStub?(path)) ?? .test()
    }
    
    var invokedLoadPackageInfo = false
    var invokedLoadPackageInfoCount = 0
    var invokedLoadPackageInfoParameters: AbsolutePath?
    var invokedLoadPackageInfoParametersList = [AbsolutePath]()
    var loadPackageInfoStub: ((AbsolutePath) throws  -> PackageInfo)?
    
    public func loadPackageInfo(at path: AbsolutePath) throws -> PackageInfo {
        invokedLoadPackageInfo = true
        invokedLoadPackageInfoCount += 1
        invokedLoadPackageInfoParameters = path
        invokedLoadPackageInfoParametersList.append(path)
        return (try loadPackageInfoStub?(path)) ?? .test()
    }
}
