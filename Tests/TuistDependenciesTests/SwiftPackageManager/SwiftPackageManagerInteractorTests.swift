import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistDependencies
@testable import TuistDependenciesTesting
@testable import TuistSupportTesting

final class SwiftPackageManagerInteractorTests: TuistUnitTestCase {
    private var subject: SwiftPackageManagerInteractor!
    
    private var swiftPackageManager: MockSwiftPackageManager!
    private var xcframeworksBuilder: MockXCFrameworkBuilder!

    override func setUp() {
        super.setUp()

        swiftPackageManager = MockSwiftPackageManager()
        xcframeworksBuilder = MockXCFrameworkBuilder()
        
        subject = SwiftPackageManagerInteractor(
            swiftPackageManager: swiftPackageManager,
            xcframeworkBuilder: xcframeworksBuilder
        )
    }

    override func tearDown() {
        subject = nil
        
        swiftPackageManager = nil
        xcframeworksBuilder = nil

        super.tearDown()
    }

    func test_fetch() throws {
        // Given
        let workingPath = try temporaryPath()
        
        let rootPath = try TemporaryDirectory(removeTreeOnDeinit: true).path
        let dependenciesDirectory = rootPath
            .appending(component: Constants.DependenciesDirectory.name)
        let lockfilesDirectory = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.lockfilesDirectoryName)
        let swiftPackageManagerDirectory = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.swiftPackageManagerDirectoryName)
        let buildDirectory = swiftPackageManagerDirectory
            .appending(component: ".build")

        let depedencies = SwiftPackageManagerDependencies([
            .remote(url: "https://github.com/Alamofire/Alamofire.git", requirement: .upToNextMajor("5.2.0")),
        ])
        let platforms = Set<Platform>([.iOS])
        
        let packageDependency = PackageDependency.test(
            name: "Alamofire",
            path: "/path/to/dependency"
        )
        let packageInfo = PackageInfo.test(
            name: "Alamofire",
            platforms: [.init(platformName: "ios", version: "12.0")]
        )
        
        swiftPackageManager.resolveStub = { [fileHandler] path in
            try [
                "Package.resolved",
                ".build/manifest.db",
                ".build/workspace-state.json",
                ".build/artifacts/foo.txt",
                ".build/checkouts/Alamofire/Info.plist",
                ".build/repositories/checkouts-state.json",
                ".build/repositories/Alamofire-e8f130fe/config",
            ].forEach {
                try fileHandler!.touch(path.appending(RelativePath($0)))
            }
        }
        swiftPackageManager.loadDependenciesStub = { _ in
            return packageDependency
        }
        swiftPackageManager.loadPackageInfoStub = { _ in
            return packageInfo
        }
        xcframeworksBuilder.buildXCFrameworkStub = { [fileHandler] arguments in
            let xcframeworkPath = arguments.outputDirectory.appending(component: "Alamofire.xcframework")
            try fileHandler!.touch(xcframeworkPath)
            
            return [
                xcframeworkPath
            ]
        }

        // When
        try subject.fetch(
            dependenciesDirectory: dependenciesDirectory,
            dependencies: depedencies,
            platforms: platforms
        )

        // Then
        XCTAssertTrue(swiftPackageManager.invokedResolve)
        XCTAssertEqual(swiftPackageManager.invokedResolveCount, 1)
        XCTAssertEqual(swiftPackageManager.invokedResolveParameters, workingPath)
        
        XCTAssertTrue(swiftPackageManager.invokedLoadDependencies)
        XCTAssertEqual(swiftPackageManager.invokedLoadDependenciesCount, 1)
        XCTAssertEqual(swiftPackageManager.invokedLoadDependenciesParameters, workingPath)
        
        XCTAssertTrue(swiftPackageManager.invokedLoadPackageInfo)
        XCTAssertEqual(swiftPackageManager.invokedLoadPackageInfoCount, 1)
        XCTAssertEqual(swiftPackageManager.invokedLoadPackageInfoParameters, packageDependency.absolutePath)
        
        XCTAssertTrue(swiftPackageManager.invokedGenerateXcodeProject)
        XCTAssertEqual(swiftPackageManager.invokedGenerateXcodeProjectCount, 1)
        XCTAssertEqual(swiftPackageManager.invokedGenerateXcodeProjectParameters?.0, packageDependency.absolutePath)
        XCTAssertEqual(swiftPackageManager.invokedGenerateXcodeProjectParameters?.1, workingPath.appending(component: "Alamofire"))
        
        XCTAssertTrue(xcframeworksBuilder.invokedBuildXCFrameworks)
        XCTAssertEqual(xcframeworksBuilder.invokedBuildXCFrameworksCount, 1)
        XCTAssertEqual(xcframeworksBuilder.invokedBuildXCFrameworksParameters?.packageInfo, packageInfo)
        XCTAssertEqual(xcframeworksBuilder.invokedBuildXCFrameworksParameters?.outputDirectory, workingPath.appending(component: "Alamofire"))
        XCTAssertEqual(xcframeworksBuilder.invokedBuildXCFrameworksParameters?.platforms, [.iOS])

        XCTAssertDirectoryContentEqual(dependenciesDirectory, [
            Constants.DependenciesDirectory.lockfilesDirectoryName,
            Constants.DependenciesDirectory.swiftPackageManagerDirectoryName,
        ])
        XCTAssertDirectoryContentEqual(lockfilesDirectory, [
            Constants.DependenciesDirectory.packageResolvedName
        ])
        XCTAssertDirectoryContentEqual(swiftPackageManagerDirectory, [
            ".build",
            "Alamofire.xcframework",
        ])
        XCTAssertDirectoryContentEqual(buildDirectory, [
            "manifest.db",
            "workspace-state.json",
            "artifacts",
            "checkouts",
            "repositories",
        ])
    }
    
    func test_fetch_when_dependenciesDirectoryContainsResultsFromOtherDepedenciesManager() throws {
        // Given
        let workingPath = try temporaryPath()
        
        let rootPath = try TemporaryDirectory(removeTreeOnDeinit: true).path
        let dependenciesDirectory = rootPath
            .appending(component: Constants.DependenciesDirectory.name)
        let lockfilesDirectory = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.lockfilesDirectoryName)
        let swiftPackageManagerDirectory = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.swiftPackageManagerDirectoryName)
        let buildDirectory = swiftPackageManagerDirectory
            .appending(component: ".build")
        let otherDependenciesManagerDirectory = dependenciesDirectory
            .appending(component: "OtherDepedenciesManager")

        let depedencies = SwiftPackageManagerDependencies([
            .remote(url: "https://github.com/Alamofire/Alamofire.git", requirement: .upToNextMajor("5.2.0")),
        ])
        let platforms = Set<Platform>([.iOS])
        
        let packageDependency = PackageDependency.test(
            name: "Alamofire",
            path: "/path/to/dependency"
        )
        let packageInfo = PackageInfo.test(
            name: "Alamofire",
            platforms: [.init(platformName: "ios", version: "12.0")]
        )
        
        try fileHandler.touch(lockfilesDirectory.appending(component: "OtherLockfile.lock"))
        try fileHandler.touch(dependenciesDirectory.appending(components: "OtherDepedenciesManager", "Info.plist"))
        
        swiftPackageManager.resolveStub = { [fileHandler] path in
            try [
                "Package.resolved",
                ".build/manifest.db",
                ".build/workspace-state.json",
                ".build/artifacts/foo.txt",
                ".build/checkouts/Alamofire/Info.plist",
                ".build/repositories/checkouts-state.json",
                ".build/repositories/Alamofire-e8f130fe/config",
            ].forEach {
                try fileHandler!.touch(path.appending(RelativePath($0)))
            }
        }
        swiftPackageManager.loadDependenciesStub = { _ in
            return packageDependency
        }
        swiftPackageManager.loadPackageInfoStub = { _ in
            return packageInfo
        }
        xcframeworksBuilder.buildXCFrameworkStub = { [fileHandler] arguments in
            let xcframeworkPath = arguments.outputDirectory.appending(component: "Alamofire.xcframework")
            try fileHandler!.touch(xcframeworkPath)
            
            return [
                xcframeworkPath
            ]
        }

        // When
        try subject.fetch(
            dependenciesDirectory: dependenciesDirectory,
            dependencies: depedencies,
            platforms: platforms
        )

        // Then
        XCTAssertTrue(swiftPackageManager.invokedResolve)
        XCTAssertEqual(swiftPackageManager.invokedResolveCount, 1)
        XCTAssertEqual(swiftPackageManager.invokedResolveParameters, workingPath)
        
        XCTAssertTrue(swiftPackageManager.invokedResolve)
        XCTAssertEqual(swiftPackageManager.invokedResolveCount, 1)
        XCTAssertEqual(swiftPackageManager.invokedResolveParameters, workingPath)
        
        XCTAssertTrue(swiftPackageManager.invokedLoadDependencies)
        XCTAssertEqual(swiftPackageManager.invokedLoadDependenciesCount, 1)
        XCTAssertEqual(swiftPackageManager.invokedLoadDependenciesParameters, workingPath)
        
        XCTAssertTrue(swiftPackageManager.invokedLoadPackageInfo)
        XCTAssertEqual(swiftPackageManager.invokedLoadPackageInfoCount, 1)
        XCTAssertEqual(swiftPackageManager.invokedLoadPackageInfoParameters, packageDependency.absolutePath)
        
        XCTAssertTrue(swiftPackageManager.invokedGenerateXcodeProject)
        XCTAssertEqual(swiftPackageManager.invokedGenerateXcodeProjectCount, 1)
        XCTAssertEqual(swiftPackageManager.invokedGenerateXcodeProjectParameters?.0, packageDependency.absolutePath)
        XCTAssertEqual(swiftPackageManager.invokedGenerateXcodeProjectParameters?.1, workingPath.appending(component: "Alamofire"))
        
        XCTAssertTrue(xcframeworksBuilder.invokedBuildXCFrameworks)
        XCTAssertEqual(xcframeworksBuilder.invokedBuildXCFrameworksCount, 1)
        XCTAssertEqual(xcframeworksBuilder.invokedBuildXCFrameworksParameters?.packageInfo, packageInfo)
        XCTAssertEqual(xcframeworksBuilder.invokedBuildXCFrameworksParameters?.outputDirectory, workingPath.appending(component: "Alamofire"))
        XCTAssertEqual(xcframeworksBuilder.invokedBuildXCFrameworksParameters?.platforms, [.iOS])

        XCTAssertDirectoryContentEqual(dependenciesDirectory, [
            Constants.DependenciesDirectory.lockfilesDirectoryName,
            Constants.DependenciesDirectory.swiftPackageManagerDirectoryName,
            "OtherDepedenciesManager",
        ])
        XCTAssertDirectoryContentEqual(lockfilesDirectory, [
            Constants.DependenciesDirectory.packageResolvedName,
            "OtherLockfile.lock"
        ])
        XCTAssertDirectoryContentEqual(swiftPackageManagerDirectory, [
           ".build",
            "Alamofire.xcframework",
        ])
        XCTAssertDirectoryContentEqual(buildDirectory, [
            "manifest.db",
            "workspace-state.json",
            "artifacts",
            "checkouts",
            "repositories",
        ])
        XCTAssertDirectoryContentEqual(otherDependenciesManagerDirectory, [
            "Info.plist",
        ])
    }
    
    func test_clean() throws {
        // Given
        let rootPath = try temporaryPath()
        let dependenciesDirectory = rootPath
            .appending(component: Constants.DependenciesDirectory.name)
        let lockfilesDirectory = dependenciesDirectory
            .appending(component: Constants.DependenciesDirectory.lockfilesDirectoryName)
        let otherDependenciesManagerDirectory = dependenciesDirectory
            .appending(component: "OtherDepedenciesManager")
        
        try createFiles([
            "Dependencies/Lockfiles/Package.resolved",
            "Dependencies/Lockfiles/OtherLockfile.lock",
            "Dependencies/SwiftPackageManager/Info.plist",
            "Dependencies/OtherDepedenciesManager/Bar.bar",
        ])
        
        // When
        try subject.clean(dependenciesDirectory: dependenciesDirectory)
        
        // Then
        XCTAssertDirectoryContentEqual(dependenciesDirectory, [
            Constants.DependenciesDirectory.lockfilesDirectoryName,
            "OtherDepedenciesManager"
        ])
        XCTAssertDirectoryContentEqual(lockfilesDirectory, [
            "OtherLockfile.lock"
        ])
        XCTAssertDirectoryContentEqual(otherDependenciesManagerDirectory, [
            "Bar.bar"
        ])
    }
}
