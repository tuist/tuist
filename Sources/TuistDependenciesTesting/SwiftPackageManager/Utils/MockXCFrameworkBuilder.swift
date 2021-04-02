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
        at path: AbsolutePath,
        packageInfo: PackageInfo,
        platforms: Set<Platform>
    ) throws -> [AbsolutePath] {
        let parameters = BuildXCFrameworksParameters(
            path: path,
            packageInfo: packageInfo,
            platforms: platforms
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
    struct BuildXCFrameworksParameters: Equatable {
        let path: AbsolutePath
        let packageInfo: PackageInfo
        let platforms: Set<Platform>
    }
}
