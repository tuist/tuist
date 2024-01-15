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
        let frameworkPath = fixturePath(path: try RelativePath(validating: "MyFramework.xcframework"))
        let infoPlist = try subject.infoPlist(xcframeworkPath: frameworkPath)

        // Then
        XCTAssertEqual(infoPlist.libraries, [
            .init(
                identifier: "ios-x86_64-simulator",
                path: try RelativePath(validating: "MyFramework.framework"),
                mergeable: false,
                architectures: [.x8664]
            ),
            .init(
                identifier: "ios-arm64",
                path: try RelativePath(validating: "MyFramework.framework"),
                mergeable: false,
                architectures: [.arm64]
            ),
        ])
        infoPlist.libraries.forEach { XCTAssertEqual($0.binaryName, "MyFramework") }
    }

    func test_binaryPath_when_frameworkIsPresent() throws {
        // Given
        let frameworkPath = fixturePath(path: try RelativePath(validating: "MyFramework.xcframework"))
        let infoPlist = try subject.infoPlist(xcframeworkPath: frameworkPath)
        let binaryPath = try subject.binaryPath(xcframeworkPath: frameworkPath, libraries: infoPlist.libraries)

        // Then
        XCTAssertEqual(
            binaryPath,
            frameworkPath.appending(try RelativePath(validating: "ios-x86_64-simulator/MyFramework.framework/MyFramework"))
        )
    }

    func test_binaryPath_when_frameworkIsPresentAndHasDifferentName() throws {
        // Given
        let frameworkPath = fixturePath(path: try RelativePath(validating: "MyFrameworkDifferentProductName.xcframework"))
        let infoPlist = try subject.infoPlist(xcframeworkPath: frameworkPath)
        let binaryPath = try subject.binaryPath(xcframeworkPath: frameworkPath, libraries: infoPlist.libraries)

        // Then
        XCTAssertEqual(
            binaryPath,
            frameworkPath.appending(try RelativePath(validating: "ios-x86_64-simulator/MyFramework.framework/MyFramework"))
        )

        infoPlist.libraries.forEach { XCTAssertEqual($0.binaryName, "MyFramework") }
    }

    func test_libraries_when_staticLibraryIsPresent() throws {
        // Given
        let frameworkPath = fixturePath(path: try RelativePath(validating: "MyStaticLibrary.xcframework"))
        let infoPlist = try subject.infoPlist(xcframeworkPath: frameworkPath)

        // Then
        XCTAssertEqual(infoPlist.libraries, [
            .init(
                identifier: "ios-x86_64-simulator",
                path: try RelativePath(validating: "libMyStaticLibrary.a"),
                mergeable: false,
                architectures: [.x8664]
            ),
            .init(
                identifier: "ios-arm64",
                path: try RelativePath(validating: "libMyStaticLibrary.a"),
                mergeable: false,
                architectures: [.arm64]
            ),
        ])
        infoPlist.libraries.forEach { XCTAssertEqual($0.binaryName, "libMyStaticLibrary") }
    }

    func test_binaryPath_when_staticLibraryIsPresent() throws {
        // Given
        let frameworkPath = fixturePath(path: try RelativePath(validating: "MyStaticLibrary.xcframework"))
        let infoPlist = try subject.infoPlist(xcframeworkPath: frameworkPath)
        let binaryPath = try subject.binaryPath(xcframeworkPath: frameworkPath, libraries: infoPlist.libraries)

        // Then
        XCTAssertEqual(
            binaryPath,
            frameworkPath.appending(try RelativePath(validating: "ios-x86_64-simulator/libMyStaticLibrary.a"))
        )
    }

    func test_loadMetadata_dynamicLibrary() throws {
        // Given
        let frameworkPath = fixturePath(path: try RelativePath(validating: "MyFramework.xcframework"))

        // When
        let metadata = try subject.loadMetadata(at: frameworkPath, status: .required)

        // Then
        let expectedInfoPlist = XCFrameworkInfoPlist(libraries: [
            .init(
                identifier: "ios-x86_64-simulator",
                path: try RelativePath(validating: "MyFramework.framework"),
                mergeable: false,
                architectures: [.x8664]
            ),
            .init(
                identifier: "ios-arm64",
                path: try RelativePath(validating: "MyFramework.framework"),
                mergeable: false,
                architectures: [.arm64]
            ),
        ])

        let expectedBinaryPath = frameworkPath
            .appending(try RelativePath(validating: "ios-x86_64-simulator/MyFramework.framework/MyFramework"))
        XCTAssertEqual(metadata, XCFrameworkMetadata(
            path: frameworkPath,
            infoPlist: expectedInfoPlist,
            primaryBinaryPath: expectedBinaryPath,
            linking: .dynamic,
            mergeable: false,
            status: .required,
            macroPath: nil
        ))
    }

    func test_loadMetadata_mergeableDynamicLibrary() throws {
        // Given
        let frameworkPath = fixturePath(path: try RelativePath(validating: "MyMergeableFramework.xcframework"))

        // When
        let metadata = try subject.loadMetadata(at: frameworkPath, status: .required)

        // Then
        let expectedInfoPlist = XCFrameworkInfoPlist(libraries: [
            .init(
                identifier: "ios-x86_64-simulator",
                path: try RelativePath(validating: "MyMergeableFramework.framework"),
                mergeable: true,
                architectures: [.x8664]
            ),
            .init(
                identifier: "ios-arm64",
                path: try RelativePath(validating: "MyMergeableFramework.framework"),
                mergeable: true,
                architectures: [.arm64]
            ),
        ])
        let relativePath =
            try RelativePath(validating: "ios-x86_64-simulator/MyMergeableFramework.framework/MyMergeableFramework")
        let expectedBinaryPath = frameworkPath.appending(relativePath)
        XCTAssertEqual(metadata, XCFrameworkMetadata(
            path: frameworkPath,
            infoPlist: expectedInfoPlist,
            primaryBinaryPath: expectedBinaryPath,
            linking: .dynamic,
            mergeable: true,
            status: .required,
            macroPath: nil
        ))
    }

    func test_loadMetadata_staticLibrary() throws {
        // Given
        let frameworkPath = fixturePath(path: try RelativePath(validating: "MyStaticLibrary.xcframework"))

        // When
        let metadata = try subject.loadMetadata(at: frameworkPath, status: .required)

        // Then
        let expectedInfoPlist = XCFrameworkInfoPlist(libraries: [
            .init(
                identifier: "ios-x86_64-simulator",
                path: try RelativePath(validating: "libMyStaticLibrary.a"),
                mergeable: false,
                architectures: [.x8664]
            ),
            .init(
                identifier: "ios-arm64",
                path: try RelativePath(validating: "libMyStaticLibrary.a"),
                mergeable: false,
                architectures: [.arm64]
            ),
        ])
        let expectedBinaryPath = frameworkPath
            .appending(try RelativePath(validating: "ios-x86_64-simulator/libMyStaticLibrary.a"))
        XCTAssertEqual(metadata, XCFrameworkMetadata(
            path: frameworkPath,
            infoPlist: expectedInfoPlist,
            primaryBinaryPath: expectedBinaryPath,
            linking: .static,
            mergeable: false,
            status: .required,
            macroPath: nil
        ))
    }

    func test_loadMetadata_frameworkMissingArchitecture() throws {
        // Given
        let frameworkPath = fixturePath(path: try RelativePath(validating: "MyFrameworkMissingArch.xcframework"))

        // When
        let metadata = try subject.loadMetadata(at: frameworkPath, status: .required)

        // Then
        let expectedInfoPlist = XCFrameworkInfoPlist(libraries: [
            .init(
                identifier: "ios-x86_64-simulator", // Not present on disk
                path: try RelativePath(validating: "MyFrameworkMissingArch.framework"),
                mergeable: false,
                architectures: [.x8664]
            ),
            .init(
                identifier: "ios-arm64",
                path: try RelativePath(validating: "MyFrameworkMissingArch.framework"),
                mergeable: false,
                architectures: [.arm64]
            ),
        ])
        let expectedBinaryPath = frameworkPath
            .appending(try RelativePath(validating: "ios-arm64/MyFrameworkMissingArch.framework/MyFrameworkMissingArch"))
        XCTAssertEqual(metadata, XCFrameworkMetadata(
            path: frameworkPath,
            infoPlist: expectedInfoPlist,
            primaryBinaryPath: expectedBinaryPath,
            linking: .dynamic,
            mergeable: false,
            status: .required,
            macroPath: nil
        ))

        XCTAssertPrinterOutputContains("""
        MyFrameworkMissingArch.xcframework is missing architecture ios-x86_64-simulator/MyFrameworkMissingArch.framework/MyFrameworkMissingArch defined in the Info.plist
        """)
    }

    func test_loadMetadata_when_containsMacros() throws {
        // Given
        let temporaryDirectory = try temporaryPath()
        let xcframeworkPath = temporaryDirectory.appending(component: "MyFramework.xcframework")
        try fileHandler.copy(
            from: fixturePath(path: try RelativePath(validating: "MyFramework.xcframework")),
            to: xcframeworkPath
        )
        var macroPaths: [AbsolutePath] = []
        try fileHandler.glob(xcframeworkPath, glob: "*/*.framework").sorted().forEach { frameworkPath in
            try fileHandler.createFolder(frameworkPath.appending(component: "Macros"))
            let macroPath = frameworkPath.appending(components: ["Macros", "MyFramework"])
            try fileHandler.touch(macroPath)
            macroPaths.append(macroPath)
        }

        // When
        let metadata = try subject.loadMetadata(at: xcframeworkPath, status: .required)

        // Then
        XCTAssertEqual(metadata.macroPath, macroPaths.sorted().first)
    }
}
