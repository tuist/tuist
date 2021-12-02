import TSCBasic
import XCTest
@testable import TuistCore
@testable import TuistGraph
@testable import TuistSupportTesting

final class XCFrameworkMetadataProviderTests: TuistTestCase {
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
            .init(
                identifier: "ios-x86_64-simulator",
                path: RelativePath("MyFramework.framework"),
                architectures: [.x8664]
            ),
            .init(
                identifier: "ios-arm64",
                path: RelativePath("MyFramework.framework"),
                architectures: [.arm64]
            ),
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
            .init(
                identifier: "ios-x86_64-simulator",
                path: RelativePath("libMyStaticLibrary.a"),
                architectures: [.x8664]
            ),
            .init(
                identifier: "ios-arm64",
                path: RelativePath("libMyStaticLibrary.a"),
                architectures: [.arm64]
            ),
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

    func test_loadMetadata_dynamicLibrary() throws {
        // Given
        let frameworkPath = fixturePath(path: RelativePath("MyFramework.xcframework"))

        // When
        let metadata = try subject.loadMetadata(at: frameworkPath)

        // Then
        let expectedInfoPlist = XCFrameworkInfoPlist(libraries: [
            .init(
                identifier: "ios-x86_64-simulator",
                path: RelativePath("MyFramework.framework"),
                architectures: [.x8664]
            ),
            .init(
                identifier: "ios-arm64",
                path: RelativePath("MyFramework.framework"),
                architectures: [.arm64]
            ),
        ])
        let expectedBinaryPath = frameworkPath.appending(RelativePath("ios-x86_64-simulator/MyFramework.framework/MyFramework"))
        XCTAssertEqual(metadata, XCFrameworkMetadata(
            path: frameworkPath,
            infoPlist: expectedInfoPlist,
            primaryBinaryPath: expectedBinaryPath,
            linking: .dynamic
        ))
    }

    func test_loadMetadata_staticLibrary() throws {
        // Given
        let frameworkPath = fixturePath(path: RelativePath("MyStaticLibrary.xcframework"))

        // When
        let metadata = try subject.loadMetadata(at: frameworkPath)

        // Then
        let expectedInfoPlist = XCFrameworkInfoPlist(libraries: [
            .init(
                identifier: "ios-x86_64-simulator",
                path: RelativePath("libMyStaticLibrary.a"),
                architectures: [.x8664]
            ),
            .init(
                identifier: "ios-arm64",
                path: RelativePath("libMyStaticLibrary.a"),
                architectures: [.arm64]
            ),
        ])
        let expectedBinaryPath = frameworkPath.appending(RelativePath("ios-x86_64-simulator/libMyStaticLibrary.a"))
        XCTAssertEqual(metadata, XCFrameworkMetadata(
            path: frameworkPath,
            infoPlist: expectedInfoPlist,
            primaryBinaryPath: expectedBinaryPath,
            linking: .static
        ))
    }

    func test_loadMetadata_frameworkMissingArchitecture() throws {
        // Given
        let frameworkPath = fixturePath(path: RelativePath("MyFrameworkMissingArch.xcframework"))

        // When
        let metadata = try subject.loadMetadata(at: frameworkPath)

        // Then
        let expectedInfoPlist = XCFrameworkInfoPlist(libraries: [
            .init(
                identifier: "ios-x86_64-simulator", // Not present on disk
                path: RelativePath("MyFrameworkMissingArch.framework"),
                architectures: [.x8664]
            ),
            .init(
                identifier: "ios-arm64",
                path: RelativePath("MyFrameworkMissingArch.framework"),
                architectures: [.arm64]
            ),
        ])
        let expectedBinaryPath = frameworkPath
            .appending(RelativePath("ios-arm64/MyFrameworkMissingArch.framework/MyFrameworkMissingArch"))
        XCTAssertEqual(metadata, XCFrameworkMetadata(
            path: frameworkPath,
            infoPlist: expectedInfoPlist,
            primaryBinaryPath: expectedBinaryPath,
            linking: .dynamic
        ))

        XCTAssertPrinterOutputContains("""
        MyFrameworkMissingArch.xcframework is missing architecture ios-x86_64-simulator/MyFrameworkMissingArch.framework/MyFrameworkMissingArch defined in the Info.plist
        """)
    }
}
