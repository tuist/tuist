import TSCBasic
import TuistGraph

@testable import TuistDependencies

public final class MockXCFrameworkBuilder: XCFrameworkBuilding {
    public init() {}
    
    var invokedBuildXCFrameworks = false
    var invokedBuildXCFrameworksCount = 0
    var invokedBuildXCFrameworksParameters: BuildXCFrameworksParameters?
    var invokedBuildXCFrameworksParametersList = [BuildXCFrameworksParameters]()
    var buildXCFrameworkStub: ((BuildXCFrameworksParameters) throws -> [AbsolutePath])?
    
    public func buildXCFrameworks(
        using packageInfo: PackageInfo,
        platforms: Set<Platform>,
        outputDirectory: AbsolutePath
    ) throws -> [AbsolutePath] {
        let parameters = BuildXCFrameworksParameters(
            packageInfo: packageInfo,
            platforms: platforms,
            outputDirectory: outputDirectory
        )
        
        invokedBuildXCFrameworks = true
        invokedBuildXCFrameworksCount += 1
        invokedBuildXCFrameworksParameters = parameters
        invokedBuildXCFrameworksParametersList.append(parameters)
        
        return (try buildXCFrameworkStub?(parameters)) ?? []
    }
}

// MARK: - Models

extension MockXCFrameworkBuilder {
    struct BuildXCFrameworksParameters {
        let packageInfo: PackageInfo
        let platforms: Set<Platform>
        let outputDirectory: AbsolutePath
    }
}
