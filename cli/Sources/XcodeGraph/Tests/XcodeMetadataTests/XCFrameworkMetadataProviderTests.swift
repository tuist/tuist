import Path
import Testing
import XcodeGraph
@testable import XcodeMetadata

@Suite
struct XCFrameworkMetadataProviderTests {
    private var subject: XCFrameworkMetadataProvider

    init() {
        subject = XCFrameworkMetadataProvider()
    }

    @Test
    func librariesWhenFrameworkIsPresent() async throws {
        // Given
        let relativePath = try RelativePath(validating: "MyFramework.xcframework")
        let frameworkPath = AssertionsTesting.fixturePath(
            path: relativePath
        )

        // When
        let infoPlist = try await subject.infoPlist(xcframeworkPath: frameworkPath)

        // Then
        let expectedPath = try RelativePath(validating: "MyFramework.framework")
        #expect(
            infoPlist.libraries == [
                XCFrameworkInfoPlist.Library(
                    identifier: "ios-x86_64-simulator",
                    path: expectedPath,
                    mergeable: false,
                    platform: .iOS,
                    architectures: [.x8664]
                ),
                XCFrameworkInfoPlist.Library(
                    identifier: "ios-arm64",
                    path: expectedPath,
                    mergeable: false,
                    platform: .iOS,
                    architectures: [.arm64]
                ),
            ],
            "Libraries do not match expected value"
        )
        for library in infoPlist.libraries {
            #expect(library.binaryName == "MyFramework", "Binary name does not match")
        }
    }

    @Test
    func librariesWhenStaticLibraryIsPresent() async throws {
        // Given
        let relativePath = try RelativePath(validating: "MyStaticLibrary.xcframework")
        let xcframeworkPath = AssertionsTesting.fixturePath(
            path: relativePath
        )

        // When
        let infoPlist = try await subject.infoPlist(xcframeworkPath: xcframeworkPath)

        let expectedPath = try RelativePath(validating: "libMyStaticLibrary.a")

        // Then
        #expect(
            infoPlist.libraries == [
                XCFrameworkInfoPlist.Library(
                    identifier: "ios-x86_64-simulator",
                    path: expectedPath,
                    mergeable: false,
                    platform: .iOS,
                    architectures: [.x8664]
                ),
                XCFrameworkInfoPlist.Library(
                    identifier: "ios-arm64",
                    path: expectedPath,
                    mergeable: false,
                    platform: .iOS,
                    architectures: [.arm64]
                ),
            ],
            "Libraries do not match expected value"
        )
        for library in infoPlist.libraries {
            #expect(library.binaryName == "libMyStaticLibrary", "Binary name does not match")
        }
    }

    @Test
    func loadMetadataDynamicLibrary() async throws {
        // Given
        let relativePath = try RelativePath(validating: "MyFramework.xcframework")

        let frameworkPath = AssertionsTesting.fixturePath(
            path: relativePath
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

        #expect(
            metadata == XCFrameworkMetadata(
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
            ),
            "Metadata does not match expected value"
        )
    }

    @Test
    func loadMetadataMergeableDynamicLibrary() async throws {
        // Given
        let frameworkPath = AssertionsTesting.fixturePath(
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

        #expect(
            metadata == XCFrameworkMetadata(
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

    @Test
    func loadMetadataFrameworkMissingArchitecture() async throws {
        // Given
        let frameworkPath = AssertionsTesting.fixturePath(
            path: try RelativePath(validating: "MyFrameworkMissingArch.xcframework")
        )

        // When
        let metadata = try await subject.loadMetadata(at: frameworkPath, expectedSignature: nil, status: .required)

        // Then
        #expect(metadata.infoPlist.libraries.count == 2, "Libraries count mismatch")
    }
}
