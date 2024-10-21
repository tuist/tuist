import Path
import XCTest

@testable import TuistCore
@testable import TuistSupportTesting
@testable import XcodeGraph

final class XCFrameworkMetadataProviderTests: TuistUnitTestCase {
    private var subject: XCFrameworkMetadataProvider!

    override func setUp() {
        super.setUp()
        subject = XCFrameworkMetadataProvider()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_libraries_when_frameworkIsPresent() async throws {
        // Given
        let frameworkPath = fixturePath(
            path: try RelativePath(validating: "MyFramework.xcframework")
        )
        let infoPlist = try await subject.infoPlist(xcframeworkPath: frameworkPath)

        // Then
        XCTAssertEqual(
            infoPlist.libraries,
            [
                XCFrameworkInfoPlist.Library(
                    identifier: "ios-x86_64-simulator",
                    path: try RelativePath(validating: "MyFramework.framework"),
                    mergeable: false,
                    platform: .iOS,
                    architectures: [.x8664]
                ),
                XCFrameworkInfoPlist.Library(
                    identifier: "ios-arm64",
                    path: try RelativePath(validating: "MyFramework.framework"),
                    mergeable: false,
                    platform: .iOS,
                    architectures: [.arm64]
                ),
            ]
        )
        infoPlist.libraries.forEach { XCTAssertEqual($0.binaryName, "MyFramework") }
    }

    func test_libraries_when_staticLibraryIsPresent() async throws {
        // Given
        let xcframeworkPath = fixturePath(
            path: try RelativePath(validating: "MyStaticLibrary.xcframework")
        )
        let infoPlist = try await subject.infoPlist(xcframeworkPath: xcframeworkPath)

        // Then
        XCTAssertEqual(
            infoPlist.libraries,
            [
                XCFrameworkInfoPlist.Library(
                    identifier: "ios-x86_64-simulator",
                    path: try RelativePath(validating: "libMyStaticLibrary.a"),
                    mergeable: false,
                    platform: .iOS,
                    architectures: [.x8664]
                ),
                XCFrameworkInfoPlist.Library(
                    identifier: "ios-arm64",
                    path: try RelativePath(validating: "libMyStaticLibrary.a"),
                    mergeable: false,
                    platform: .iOS,
                    architectures: [.arm64]
                ),
            ]
        )
        infoPlist.libraries.forEach { XCTAssertEqual($0.binaryName, "libMyStaticLibrary") }
    }

    func test_loadMetadata_dynamicLibrary() async throws {
        // Given
        let frameworkPath = fixturePath(
            path: try RelativePath(validating: "MyFramework.xcframework")
        )

        // When
        let metadata = try await subject.loadMetadata(at: frameworkPath, status: .required)

        // Then
        let expectedInfoPlist = XCFrameworkInfoPlist(libraries: [
            XCFrameworkInfoPlist.Library(
                identifier: "ios-x86_64-simulator",
                path: try RelativePath(validating: "MyFramework.framework"),
                mergeable: false,
                platform: .iOS,
                architectures: [.x8664]
            ),
            XCFrameworkInfoPlist.Library(
                identifier: "ios-arm64",
                path: try RelativePath(validating: "MyFramework.framework"),
                mergeable: false,
                platform: .iOS,
                architectures: [.arm64]
            ),
        ])

        let expectedBinaryPath =
            frameworkPath
                .appending(
                    try RelativePath(
                        validating: "ios-x86_64-simulator/MyFramework.framework/MyFramework"
                    )
                )
        XCTAssertEqual(
            metadata,
            XCFrameworkMetadata(
                path: frameworkPath,
                infoPlist: expectedInfoPlist,
                linking: .dynamic,
                mergeable: false,
                status: .required,
                macroPath: nil
            )
        )
    }

    func test_loadMetadata_mergeableDynamicLibrary() async throws {
        // Given
        let frameworkPath = fixturePath(
            path: try RelativePath(validating: "MyMergeableFramework.xcframework")
        )

        // When
        let metadata = try await subject.loadMetadata(at: frameworkPath, status: .required)

        // Then
        let expectedInfoPlist = XCFrameworkInfoPlist(libraries: [
            XCFrameworkInfoPlist.Library(
                identifier: "ios-x86_64-simulator",
                path: try RelativePath(validating: "MyMergeableFramework.framework"),
                mergeable: true,
                platform: .iOS,
                architectures: [.x8664]
            ),
            XCFrameworkInfoPlist.Library(
                identifier: "ios-arm64",
                path: try RelativePath(validating: "MyMergeableFramework.framework"),
                mergeable: true,
                platform: .iOS,
                architectures: [.arm64]
            ),
        ])
        let relativePath =
            try RelativePath(
                validating:
                "ios-x86_64-simulator/MyMergeableFramework.framework/MyMergeableFramework"
            )
        let expectedBinaryPath = frameworkPath.appending(relativePath)
        XCTAssertEqual(
            metadata,
            XCFrameworkMetadata(
                path: frameworkPath,
                infoPlist: expectedInfoPlist,
                linking: .dynamic,
                mergeable: true,
                status: .required,
                macroPath: nil
            )
        )
    }

    func test_loadMetadata_staticLibrary() async throws {
        // Given
        let frameworkPath = fixturePath(
            path: try RelativePath(validating: "MyStaticLibrary.xcframework")
        )

        // When
        let metadata = try await subject.loadMetadata(at: frameworkPath, status: .required)

        // Then
        let expectedInfoPlist = XCFrameworkInfoPlist(libraries: [
            XCFrameworkInfoPlist.Library(
                identifier: "ios-x86_64-simulator",
                path: try RelativePath(validating: "libMyStaticLibrary.a"),
                mergeable: false,
                platform: .iOS,
                architectures: [.x8664]
            ),
            XCFrameworkInfoPlist.Library(
                identifier: "ios-arm64",
                path: try RelativePath(validating: "libMyStaticLibrary.a"),
                mergeable: false,
                platform: .iOS,
                architectures: [.arm64]
            ),
        ])
        let expectedBinaryPath =
            frameworkPath
                .appending(try RelativePath(validating: "ios-x86_64-simulator/libMyStaticLibrary.a"))
        XCTAssertEqual(
            metadata,
            XCFrameworkMetadata(
                path: frameworkPath,
                infoPlist: expectedInfoPlist,
                linking: .static,
                mergeable: false,
                status: .required,
                macroPath: nil
            )
        )
    }

    func test_loadMetadata_frameworkMissingArchitecture() async throws {
        // Given
        let frameworkPath = fixturePath(
            path: try RelativePath(validating: "MyFrameworkMissingArch.xcframework")
        )

        // When
        let metadata = try await subject.loadMetadata(at: frameworkPath, status: .required)

        // Then
        let expectedInfoPlist = XCFrameworkInfoPlist(libraries: [
            XCFrameworkInfoPlist.Library(
                identifier: "ios-x86_64-simulator", // Not present on disk
                path: try RelativePath(validating: "MyFrameworkMissingArch.framework"),
                mergeable: false,
                platform: .iOS,
                architectures: [.x8664]
            ),
            XCFrameworkInfoPlist.Library(
                identifier: "ios-arm64",
                path: try RelativePath(validating: "MyFrameworkMissingArch.framework"),
                mergeable: false,
                platform: .iOS,
                architectures: [.arm64]
            ),
        ])
        let expectedBinaryPath =
            frameworkPath
                .appending(
                    try RelativePath(
                        validating: "ios-arm64/MyFrameworkMissingArch.framework/MyFrameworkMissingArch"
                    )
                )
        XCTAssertEqual(
            metadata,
            XCFrameworkMetadata(
                path: frameworkPath,
                infoPlist: expectedInfoPlist,
                linking: .dynamic,
                mergeable: false,
                status: .required,
                macroPath: nil
            )
        )

        XCTAssertPrinterOutputContains(
            """
            MyFrameworkMissingArch.xcframework is missing architecture ios-x86_64-simulator/MyFrameworkMissingArch.framework/MyFrameworkMissingArch defined in the Info.plist
            """
        )
    }

    func test_loadMetadata_when_containsMacros() async throws {
        // Given
        let temporaryDirectory = try temporaryPath()
        let xcframeworkPath = temporaryDirectory.appending(component: "MyFramework.xcframework")
        try await fileSystem.copy(
            fixturePath(path: try RelativePath(validating: "MyFramework.xcframework")),
            to: xcframeworkPath
        )
        var macroPaths: [AbsolutePath] = []
        for frameworkPath in fileHandler.glob(xcframeworkPath, glob: "*/*.framework").sorted() {
            try fileHandler.createFolder(frameworkPath.appending(component: "Macros"))
            let macroPath = frameworkPath.appending(components: ["Macros", "MyFramework"])
            try fileHandler.touch(macroPath)
            macroPaths.append(macroPath)
        }

        // When
        let metadata = try await subject.loadMetadata(at: xcframeworkPath, status: .required)

        // Then
        XCTAssertEqual(metadata.macroPath, macroPaths.sorted().first)
    }

    func test_loadMetadataXCFrameworkDylibBinary() async throws {
        // Given
        let frameworkPath = fixturePath(path: try RelativePath(validating: "MyMath.xcframework"))

        // When
        let metadata = try await subject.loadMetadata(at: frameworkPath, status: .required)

        // Then
        let expectedInfoPlist = XCFrameworkInfoPlist(libraries: [
            XCFrameworkInfoPlist.Library(
                identifier: "ios-arm64",
                path: try RelativePath(validating: "libmymath_ios.dylib"),
                mergeable: false,
                platform: .iOS,
                architectures: [.arm64]
            ),

            XCFrameworkInfoPlist.Library(
                identifier: "ios-arm64_x86_64-simulator",
                path: try RelativePath(validating: "libmymath_ios_sim.dylib"),
                mergeable: false,
                platform: .iOS,
                architectures: [.arm64, .x8664]
            ),

            XCFrameworkInfoPlist.Library(
                identifier: "macos-arm64_x86_64",
                path: try RelativePath(validating: "libmymath_macos.dylib"),
                mergeable: false,
                platform: .macOS,
                architectures: [.arm64, .x8664]
            ),
        ])

        XCTAssertEqual(
            metadata,
            XCFrameworkMetadata(
                path: frameworkPath,
                infoPlist: expectedInfoPlist,
                linking: .dynamic,
                mergeable: false,
                status: .required,
                macroPath: nil
            )
        )
    }
}
