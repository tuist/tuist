import Path
import ServiceContextModule
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
        let metadata = try await subject.loadMetadata(at: frameworkPath, expectedSignature: nil, status: .required)

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

        XCTAssertEqual(
            metadata,
            XCFrameworkMetadata(
                path: frameworkPath,
                infoPlist: expectedInfoPlist,
                linking: .dynamic,
                mergeable: false,
                status: .required,
                macroPath: nil,
                swiftModules: [
                    frameworkPath.appending(
                        components: "ios-arm64",
                        "MyFramework.framework",
                        "Modules",
                        "MyFramework.swiftmodule"
                    ),
                    frameworkPath.appending(
                        components: "ios-x86_64-simulator",
                        "MyFramework.framework",
                        "Modules",
                        "MyFramework.swiftmodule"
                    ),
                ],
                moduleMaps: [
                    frameworkPath.appending(components: "ios-arm64", "MyFramework.framework", "Modules", "module.modulemap"),
                    frameworkPath.appending(
                        components: "ios-x86_64-simulator",
                        "MyFramework.framework",
                        "Modules",
                        "module.modulemap"
                    ),
                ]
            )
        )
    }

    func test_loadMetadata_mergeableDynamicLibrary() async throws {
        // Given
        let frameworkPath = fixturePath(
            path: try RelativePath(validating: "MyMergeableFramework.xcframework")
        )

        // When
        let metadata = try await subject.loadMetadata(at: frameworkPath, expectedSignature: nil, status: .required)

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
        XCTAssertEqual(
            metadata,
            XCFrameworkMetadata(
                path: frameworkPath,
                infoPlist: expectedInfoPlist,
                linking: .dynamic,
                mergeable: true,
                status: .required,
                macroPath: nil,
                swiftModules: [
                    frameworkPath.appending(
                        components: "ios-arm64",
                        "MyMergeableFramework.framework",
                        "Modules",
                        "MyMergeableFramework.swiftmodule"
                    ),
                    frameworkPath.appending(
                        components: "ios-arm64",
                        "MyMergeableFramework.framework",
                        "Modules",
                        "MyMergeableFramework.swiftmodule",
                        "arm64-apple-ios.swiftmodule"
                    ),
                    frameworkPath.appending(
                        components: "ios-x86_64-simulator",
                        "MyMergeableFramework.framework",
                        "Modules",
                        "MyMergeableFramework.swiftmodule"
                    ),
                    frameworkPath.appending(
                        components: "ios-x86_64-simulator",
                        "MyMergeableFramework.framework",
                        "Modules",
                        "MyMergeableFramework.swiftmodule",
                        "x86_64-apple-ios-simulator.swiftmodule"
                    ),
                ],
                moduleMaps: [
                    frameworkPath.appending(
                        components: "ios-arm64",
                        "MyMergeableFramework.framework",
                        "Modules",
                        "module.modulemap"
                    ),
                    frameworkPath.appending(
                        components: "ios-x86_64-simulator",
                        "MyMergeableFramework.framework",
                        "Modules",
                        "module.modulemap"
                    ),
                ]
            )
        )
    }

    func test_loadMetadata_staticLibrary() async throws {
        // Given
        let frameworkPath = fixturePath(
            path: try RelativePath(validating: "MyStaticLibrary.xcframework")
        )

        // When
        let metadata = try await subject.loadMetadata(at: frameworkPath, expectedSignature: nil, status: .required)

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
        try await ServiceContext.withTestingDependencies {
            // Given
            let frameworkPath = fixturePath(
                path: try RelativePath(validating: "MyFrameworkMissingArch.xcframework")
            )

            // When
            let metadata = try await subject.loadMetadata(at: frameworkPath, expectedSignature: nil, status: .required)

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
            XCTAssertEqual(
                metadata,
                XCFrameworkMetadata(
                    path: frameworkPath,
                    infoPlist: expectedInfoPlist,
                    linking: .dynamic,
                    mergeable: false,
                    status: .required,
                    macroPath: nil,
                    swiftModules: [
                        frameworkPath.appending(
                            components: "ios-arm64",
                            "MyFrameworkMissingArch.framework",
                            "Modules",
                            "MyFramework.swiftmodule"
                        ),
                    ],
                    moduleMaps: [
                        frameworkPath.appending(
                            components: "ios-arm64",
                            "MyFrameworkMissingArch.framework",
                            "Modules",
                            "module.modulemap"
                        ),
                    ]
                )
            )

            XCTAssertPrinterOutputContains(
                """
                MyFrameworkMissingArch.xcframework is missing architecture ios-x86_64-simulator/MyFrameworkMissingArch.framework/MyFrameworkMissingArch defined in the Info.plist
                """
            )
        }
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
        for frameworkPath in try await fileSystem.glob(directory: xcframeworkPath, include: ["*/*.framework"]).collect()
            .sorted()
        {
            try await fileSystem.makeDirectory(at: frameworkPath.appending(component: "Macros"))
            let macroPath = frameworkPath.appending(components: ["Macros", "MyFramework"])
            try await fileSystem.touch(macroPath)
            macroPaths.append(macroPath)
        }

        // When
        let metadata = try await subject.loadMetadata(at: xcframeworkPath, expectedSignature: nil, status: .required)

        // Then
        XCTAssertEqual(metadata.macroPath, macroPaths.sorted().first)
    }

    func test_loadMetadataXCFrameworkDylibBinary() async throws {
        // Given
        let frameworkPath = fixturePath(path: try RelativePath(validating: "MyMath.xcframework"))

        // When
        let metadata = try await subject.loadMetadata(at: frameworkPath, expectedSignature: nil, status: .required)

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
                macroPath: nil,
                moduleMaps: [
                    frameworkPath.appending(components: "ios-arm64", "Headers", "module.modulemap"),
                    frameworkPath.appending(components: "ios-arm64_x86_64-simulator", "Headers", "module.modulemap"),
                    frameworkPath.appending(components: "macos-arm64_x86_64", "Headers", "module.modulemap"),
                ]
            )
        )
    }
}
