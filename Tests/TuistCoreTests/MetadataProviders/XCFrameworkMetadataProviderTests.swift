import Basic
import XCTest

@testable import TuistCore
@testable import TuistSupportTesting

final class XCFrameworkMetadataProviderTests: XCTestCase {
    var subject: XCFrameworkMetadataProvider!

    override func setUp() {
        super.setUp()
        subject = XCFrameworkMetadataProvider()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_libraries_when_frameworkIsPresent() throws {
        // Given
        let frameworkPath = fixturePath(path: RelativePath("MyFramework.xcframework"))
        let infoPlist = try subject.infoPlist(xcframeworkPath: frameworkPath)

        // Then
        XCTAssertEqual(infoPlist.libraries, [
            .init(identifier: "ios-x86_64-simulator",
                  path: RelativePath("MyFramework.framework"),
                  architectures: [.x8664]),
            .init(identifier: "ios-arm64",
                  path: RelativePath("MyFramework.framework"),
                  architectures: [.arm64]),
        ])
    }

    func test_binaryPath_when_frameworkIsPresent() throws {
        // Given
        let frameworkPath = fixturePath(path: RelativePath("MyFramework.xcframework"))
        let infoPlist = try subject.infoPlist(xcframeworkPath: frameworkPath)
        let binaryPath = try subject.binaryPath(xcframeworkPath: frameworkPath, libraries: infoPlist.libraries)

        // Then
        XCTAssertEqual(
            binaryPath,
            frameworkPath.appending(RelativePath("ios-x86_64-simulator/MyFramework.framework/MyFramework"))
        )
    }

    func test_libraries_when_staticLibraryIsPresent() throws {
        // Given
        let frameworkPath = fixturePath(path: RelativePath("MyStaticLibrary.xcframework"))
        let infoPlist = try subject.infoPlist(xcframeworkPath: frameworkPath)

        // Then
        XCTAssertEqual(infoPlist.libraries, [
            .init(identifier: "ios-x86_64-simulator",
                  path: RelativePath("libMyStaticLibrary.a"),
                  architectures: [.x8664]),
            .init(identifier: "ios-arm64",
                  path: RelativePath("libMyStaticLibrary.a"),
                  architectures: [.arm64]),
        ])
    }

    func test_binaryPath_when_staticLibraryIsPresent() throws {
        // Given
        let frameworkPath = fixturePath(path: RelativePath("MyStaticLibrary.xcframework"))
        let infoPlist = try subject.infoPlist(xcframeworkPath: frameworkPath)
        let binaryPath = try subject.binaryPath(xcframeworkPath: frameworkPath, libraries: infoPlist.libraries)

        // Then
        XCTAssertEqual(
            binaryPath,
            frameworkPath.appending(RelativePath("ios-x86_64-simulator/libMyStaticLibrary.a"))
        )
    }
}
