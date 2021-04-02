import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XCTest
import RxSwift

@testable import TuistDependencies
@testable import TuistSupportTesting

final class XCFrameworkBuilderTests: TuistUnitTestCase {
    private var subject: XCFrameworkBuilder!
    
    private var xcodeBuildController: MockXcodeBuildController!
    
    override func setUp() {
        super.setUp()
        
        xcodeBuildController = MockXcodeBuildController()
        
        subject = XCFrameworkBuilder(xcodeBuildController: xcodeBuildController)
    }
    
    override func tearDown() {
        subject = nil
        
        xcodeBuildController = nil
        
        super.tearDown()
    }
    
    func test_buildXCFrameworks_allPlatforms() throws  {
        // Given
        let packageInfo = PackageInfo.test(
            name: "Alamofire",
            platforms: [
                .init(platformName: "ios", version: "12.0"),
                .init(platformName: "watchos", version: "6.0"),
                .init(platformName: "tvos", version: "12.0"),
                .init(platformName: "macos", version: "11.0"),
            ]
        )
        let platforms: Set<Platform> = [.iOS, .watchOS, .tvOS, .macOS]
        let outputDirectory = try temporaryPath()
        
        xcodeBuildController.archiveStub = { parameters in
            return Observable.just(.standardOutput(.init(raw: "success")))
        }
        xcodeBuildController.createXCFrameworkStub = { parameters in
            return Observable.just(.standardOutput(.init(raw: "success")))
        }
        
        let frameworksPaths = [
            outputDirectory.appending(.init("iphoneos.xcarchive/Products/Library/Frameworks/Alamofire.framework")),
            outputDirectory.appending(.init("iphonesimulator.xcarchive/Products/Library/Frameworks/Alamofire.framework")),
            outputDirectory.appending(.init("appletvos.xcarchive/Products/Library/Frameworks/Alamofire.framework")),
            outputDirectory.appending(.init("appletvsimulator.xcarchive/Products/Library/Frameworks/Alamofire.framework")),
            outputDirectory.appending(.init("watchos.xcarchive/Products/Library/Frameworks/Alamofire.framework")),
            outputDirectory.appending(.init("watchsimulator.xcarchive/Products/Library/Frameworks/Alamofire.framework")),
            outputDirectory.appending(.init("macosx.xcarchive/Products/Library/Frameworks/Alamofire.framework")),
        ]
        
        try frameworksPaths
            .forEach { try fileHandler.touch($0) }
        
        // When
        let got = try subject.buildXCFrameworks(
            at: outputDirectory,
            packageInfo: packageInfo,
            platforms: platforms
        )
        
        // Then
        let expected: [AbsolutePath] = [
            outputDirectory.appending(component: "Alamofire.xcframework")
        ]
        XCTAssertEqual(got, expected)
        
        let expectedXcodeProjectPath = outputDirectory.appending(component: packageInfo.xcodeProjectName)
        let expectedScheme = packageInfo.scheme
        XCTAssertEqual(xcodeBuildController.invokedArchiveCount, 7)
        XCTAssertTrue(xcodeBuildController.invokedArchiveParametersList.contains(
            .init(
                target: .project(expectedXcodeProjectPath),
                scheme: expectedScheme,
                clean: false,
                archivePath: outputDirectory.appending(.init("iphoneos.xcarchive")),
                arguments: [
                    .destination("generic/platform=iOS"),
                    .xcarg("SKIP_INSTALL", "NO"),
                    .xcarg("BUILD_LIBRARY_FOR_DISTRIBUTION", "YES")
                ]
            )
        ))
        XCTAssertTrue(xcodeBuildController.invokedArchiveParametersList.contains(
            .init(
                target: .project(expectedXcodeProjectPath),
                scheme: expectedScheme,
                clean: false,
                archivePath: outputDirectory.appending(.init("iphonesimulator.xcarchive")),
                arguments: [
                    .destination("generic/platform=iOS Simulator"),
                    .xcarg("SKIP_INSTALL", "NO"),
                    .xcarg("BUILD_LIBRARY_FOR_DISTRIBUTION", "YES")
                ]
            )
        ))
        XCTAssertTrue(xcodeBuildController.invokedArchiveParametersList.contains(
            .init(
                target: .project(expectedXcodeProjectPath),
                scheme: expectedScheme,
                clean: false,
                archivePath: outputDirectory.appending(.init("appletvos.xcarchive")),
                arguments: [
                    .destination("generic/platform=tvOS"),
                    .xcarg("SKIP_INSTALL", "NO"),
                    .xcarg("BUILD_LIBRARY_FOR_DISTRIBUTION", "YES")
                ]
            )
        ))
        XCTAssertTrue(xcodeBuildController.invokedArchiveParametersList.contains(
            .init(
                target: .project(expectedXcodeProjectPath),
                scheme: expectedScheme,
                clean: false,
                archivePath: outputDirectory.appending(.init("appletvsimulator.xcarchive")),
                arguments: [
                    .destination("generic/platform=tvOS Simulator"),
                    .xcarg("SKIP_INSTALL", "NO"),
                    .xcarg("BUILD_LIBRARY_FOR_DISTRIBUTION", "YES")
                ]
            )
        ))
        XCTAssertTrue(xcodeBuildController.invokedArchiveParametersList.contains(
            .init(
                target: .project(expectedXcodeProjectPath),
                scheme: expectedScheme,
                clean: false,
                archivePath: outputDirectory.appending(.init("watchos.xcarchive")),
                arguments: [
                    .destination("generic/platform=watchOS"),
                    .xcarg("SKIP_INSTALL", "NO"),
                    .xcarg("BUILD_LIBRARY_FOR_DISTRIBUTION", "YES")
                ]
            )
        ))
        XCTAssertTrue(xcodeBuildController.invokedArchiveParametersList.contains(
            .init(
                target: .project(expectedXcodeProjectPath),
                scheme: expectedScheme,
                clean: false,
                archivePath: outputDirectory.appending(.init("watchsimulator.xcarchive")),
                arguments: [
                    .destination("generic/platform=watchOS Simulator"),
                    .xcarg("SKIP_INSTALL", "NO"),
                    .xcarg("BUILD_LIBRARY_FOR_DISTRIBUTION", "YES")
                ]
            )
        ))
        XCTAssertTrue(xcodeBuildController.invokedArchiveParametersList.contains(
            .init(
                target: .project(expectedXcodeProjectPath),
                scheme: expectedScheme,
                clean: false,
                archivePath: outputDirectory.appending(.init("macosx.xcarchive")),
                arguments: [
                    .destination("generic/platform=macOS"),
                    .xcarg("SKIP_INSTALL", "NO"),
                    .xcarg("BUILD_LIBRARY_FOR_DISTRIBUTION", "YES")
                ]
            )
        ))
            
        XCTAssertEqual(xcodeBuildController.invokedCreateXCFrameworkCount, 1)
        XCTAssertEqual(xcodeBuildController.invokedCreateXCFrameworkParameters?.frameworks.sorted(), frameworksPaths.sorted())
        XCTAssertEqual(xcodeBuildController.invokedCreateXCFrameworkParameters?.output, outputDirectory.appending(component: "Alamofire.xcframework"))
    }
}
