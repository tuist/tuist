import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
@_spi(TuistLoader) import ProjectDescription
import Testing
import TSCUtility
import TuistConstants
import TuistCore
import TuistSupport
import XcodeGraph
@testable import TuistLoader
@testable import TuistTesting

@Suite(.withMockedSwiftBackDeploymentLibrariesProvider, .withMockedSDKDeploymentTargetsProvider)
struct PackageInfoMapperTests {
    private var subject: PackageInfoMapper!
    private let fileSystem = FileSystem()

    init() throws {
        let swiftVersionProviderMock = try #require(SwiftVersionProvider.mocked)
        given(swiftVersionProviderMock)
            .swiftVersion()
            .willReturn("5.9")
        let sdkDeploymentTargetsProviderMock = try #require(SDKDeploymentTargetsProvider.mocked)
        given(sdkDeploymentTargetsProviderMock)
            .minimumDeploymentTargets()
            .willReturn(.none)
        let swiftBackDeploymentLibrariesProviderMock = try #require(SwiftBackDeploymentLibrariesProvider.mocked)
        given(swiftBackDeploymentLibrariesProviderMock)
            .runpathSearchPaths()
            .willReturn([])
        subject = PackageInfoMapper()
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func resolveDependencies_whenProductContainsBinaryTargetWithUrl_mapsToXcframework(
    ) async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Sources/Target_1")))
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Sources/Target_2")))
        let resolvedDependencies = try await subject.resolveExternalDependencies(
            path: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target_1", "Target_2"]),
                    ],
                    targets: [
                        .test(name: "Target_1", type: .binary, url: "https://binary.target.com/target1.xcframework.zip"),
                        .test(name: "Target_2"),
                    ],
                    platforms: [.ios]
                ),
            ],
            packageToFolder: ["Package": basePath],
            packageToTargetsToArtifactPaths: ["Package": [
                "Target_1": try
                    .init(validating: "/artifacts/Package/Target_1.xcframework"),
            ]],
            packageModuleAliases: [:],
            packageSettings: .test()
        )

        #expect(
            resolvedDependencies.products ==
                [
                    "Product1": [
                        .xcframework(path: "/artifacts/Package/Target_1.xcframework"),
                        .project(target: "Target_2", path: .relativeToManifest(basePath.pathString)),
                    ],
                ]
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func resolveDependencies_whenProductContainsStaticLibraryArtifactBundleWithUrl_mapsToGeneratedXcframework(
    ) async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let artifactBundlePath = basePath.appending(
            components: "artifacts", "Package", "Target_1", "Target_1.artifactbundle"
        )
        try await makeStaticLibraryArtifactBundle(at: artifactBundlePath, targetName: "Target_1")
        let generatedXCFrameworkPath = try await generatedStaticLibraryArtifactBundleXCFrameworkPath(
            basePath: basePath,
            packageName: "Package",
            targetName: "Target_1",
            artifactBundlePath: artifactBundlePath
        )

        let resolvedDependencies = try await subject.resolveExternalDependencies(
            path: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target_1", "Target_2"]),
                    ],
                    targets: [
                        .test(
                            name: "Target_1",
                            type: .binary,
                            url: "https://binary.target.com/target1.artifactbundle.zip"
                        ),
                        .test(name: "Target_2"),
                    ],
                    platforms: [.ios]
                ),
            ],
            packageToFolder: ["Package": basePath],
            packageToTargetsToArtifactPaths: ["Package": [
                "Target_1": artifactBundlePath,
            ]],
            packageModuleAliases: [:],
            packageSettings: .test()
        )

        #expect(
            resolvedDependencies.products ==
                [
                    "Product1": [
                        .xcframework(path: .path(generatedXCFrameworkPath.pathString)),
                        .project(target: "Target_2", path: .relativeToManifest(basePath.pathString)),
                    ],
                ]
        )

        let infoPlist: XCFrameworkInfoPlist = try await fileSystem.readPlistFile(
            at: generatedXCFrameworkPath.appending(component: "Info.plist")
        )
        let rawInfoPlist = try #require(
            PropertyListSerialization.propertyList(
                from: Data(
                    contentsOf: URL(
                        fileURLWithPath: generatedXCFrameworkPath.appending(component: "Info.plist").pathString
                    )
                ),
                options: [],
                format: nil
            ) as? [String: Any]
        )
        let availableLibraries = try #require(rawInfoPlist["AvailableLibraries"] as? [[String: Any]])
        #expect(infoPlist.libraries.map(\.identifier).sorted() == ["apple-ios-device", "apple-ios-simulator"])
        #expect(infoPlist.libraries.map(\.headersPath) == [
            try RelativePath(validating: "Headers"),
            try RelativePath(validating: "Headers"),
        ])
        #expect(rawInfoPlist["CFBundlePackageType"] as? String == "XFWK")
        #expect(rawInfoPlist["XCFrameworkFormatVersion"] as? String == "1.0")
        #expect(availableLibraries.allSatisfy { $0["BinaryPath"] as? String == $0["LibraryPath"] as? String })
        #expect(try await fileSystem.exists(generatedXCFrameworkPath.appending(components: "apple-ios-device", "Headers")))
        #expect(try await fileSystem.exists(generatedXCFrameworkPath.appending(components: "apple-ios-simulator", "Headers")))
        #expect(
            try await fileSystem.resolveSymbolicLink(
                generatedXCFrameworkPath.appending(components: "apple-ios-device", "libTarget_1.a")
            ) ==
                artifactBundlePath.appending(components: "apple-ios-device", "libTarget_1.a")
        )
        #expect(
            try await fileSystem.resolveSymbolicLink(
                generatedXCFrameworkPath.appending(components: "apple-ios-device", "Headers", "Target_1.h")
            ) ==
                artifactBundlePath.appending(components: "include", "Target_1.h")
        )

        let updatedInfo = try await fileSystem.readTextFile(at: artifactBundlePath.appending(component: "info.json"))
            .replacingOccurrences(of: "\"version\": \"1.0.0\"", with: "\"version\": \"2.0.0\"")
        try await fileSystem.writeText(updatedInfo, at: artifactBundlePath.appending(component: "info.json"))
        let updatedGeneratedXCFrameworkPath = try await generatedStaticLibraryArtifactBundleXCFrameworkPath(
            basePath: basePath,
            packageName: "Package",
            targetName: "Target_1",
            artifactBundlePath: artifactBundlePath
        )
        #expect(updatedGeneratedXCFrameworkPath != generatedXCFrameworkPath)

        let updatedResolvedDependencies = try await subject.resolveExternalDependencies(
            path: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target_1", "Target_2"]),
                    ],
                    targets: [
                        .test(
                            name: "Target_1",
                            type: .binary,
                            url: "https://binary.target.com/target1.artifactbundle.zip"
                        ),
                        .test(name: "Target_2"),
                    ],
                    platforms: [.ios]
                ),
            ],
            packageToFolder: ["Package": basePath],
            packageToTargetsToArtifactPaths: ["Package": [
                "Target_1": artifactBundlePath,
            ]],
            packageModuleAliases: [:],
            packageSettings: .test()
        )
        #expect(
            updatedResolvedDependencies.products ==
                [
                    "Product1": [
                        .xcframework(path: .path(updatedGeneratedXCFrameworkPath.pathString)),
                        .project(target: "Target_2", path: .relativeToManifest(basePath.pathString)),
                    ],
                ]
        )
    }

    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func resolveDependencies_whenProductContainsBinaryTargetWithPathToXcframework_mapsToXcframework() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Sources/Target_1")))
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Sources/Target_2")))
        let resolvedDependencies = try await subject.resolveExternalDependencies(
            path: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target_1", "Target_2"]),
                    ],
                    targets: [
                        .test(name: "Target_1", type: .binary, path: "Sources/Target_1/Target_1.xcframework"),
                        .test(name: "Target_2"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ],
            packageToFolder: ["Package": basePath],
            packageToTargetsToArtifactPaths: [:],
            packageModuleAliases: [:],
            packageSettings: .test()
        )

        #expect(
            resolvedDependencies.products ==
                [
                    "Product1": [
                        .xcframework(path: "\(basePath)/Sources/Target_1/Target_1.xcframework"),
                        .project(target: "Target_2", path: .relativeToManifest(basePath.pathString)),
                    ],
                ]
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func resolveDependencies_whenProductContainsBinaryTargetWithPathToZip_mapsToXcframework(
    ) async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Sources/Target_1")))
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Sources/Target_2")))
        let resolvedDependencies = try await subject.resolveExternalDependencies(
            path: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target_1", "Target_2"]),
                    ],
                    targets: [
                        .test(name: "Target_1", type: .binary, path: "Sources/Target_1/Target_1.xcframework.zip"),
                        .test(name: "Target_2"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ],
            packageToFolder: ["Package": basePath],
            packageToTargetsToArtifactPaths: ["Package": [
                "Target_1": try
                    .init(validating: "/artifacts/Package/Target_1.xcframework"),
            ]],
            packageModuleAliases: [:],
            packageSettings: .test()
        )

        #expect(
            resolvedDependencies.products ==
                [
                    "Product1": [
                        .xcframework(path: "/artifacts/Package/Target_1.xcframework"),
                        .project(target: "Target_2", path: .relativeToManifest(basePath.pathString)),
                    ],
                ]
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func resolveDependencies_whenProductContainsBinaryTargetWithConfiguredSignature_mapsToSignedXcframework(
    ) async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let resolvedDependencies = try await subject.resolveExternalDependencies(
            path: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product", type: .library(.automatic), targets: ["Target"]),
                    ],
                    targets: [
                        .test(name: "Target", type: .binary, url: "https://binary.target.com/target.xcframework.zip"),
                    ],
                    platforms: [.ios]
                ),
            ],
            packageToFolder: ["Package": basePath],
            packageToTargetsToArtifactPaths: ["Package": [
                "Target": try .init(validating: "/artifacts/Package/Target.xcframework"),
            ]],
            packageModuleAliases: [:],
            packageSettings: .test(
                expectedSignatures: [
                    "Target": .signedWithAppleCertificate(teamIdentifier: "TEAMID", teamName: "TEAMNAME"),
                ]
            )
        )

        #expect(
            resolvedDependencies.products ==
                [
                    "Product": [
                        .xcframework(
                            path: "/artifacts/Package/Target.xcframework",
                            expectedSignature: .signedWithAppleCertificate(teamIdentifier: "TEAMID", teamName: "TEAMNAME")
                        ),
                    ],
                ]
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func resolveDependencies_whenProductIsPlugin_mapsToNoDependencies() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let packagePath = basePath.appending(component: "PluginPkg")

        let resolvedDependencies = try await subject.resolveExternalDependencies(
            path: basePath,
            packageInfos: [
                "PluginPkg": .test(
                    name: "PluginPkg",
                    products: [
                        .init(name: "MyBuildToolPlugin", type: .plugin, targets: ["MyBuildToolPlugin"]),
                    ],
                    targets: [
                        .test(name: "MyBuildToolPlugin", type: .plugin),
                    ],
                    platforms: [.macos]
                ),
            ],
            packageToFolder: ["PluginPkg": packagePath],
            packageToTargetsToArtifactPaths: [:],
            packageModuleAliases: [:],
            packageSettings: .test()
        )

        #expect(resolvedDependencies.products == ["MyBuildToolPlugin": []])
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func resolveDependencies_whenArtifactsContainMACOSXFolder_filtersThemOut() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let artifactsPath = basePath.appending(components: "Tuist", ".build", "artifacts", "tuist")

        // Create a valid xcframework
        let validXCFramework = artifactsPath.appending(components: "ValidFramework", "ValidFramework.xcframework")
        try await fileSystem.makeDirectory(at: validXCFramework)

        // Create a __MACOSX folder with a fake xcframework (simulating macOS zip extraction)
        let macosxFolder = artifactsPath.appending(components: "ValidFramework", "__MACOSX", "ValidFramework.xcframework")
        try await fileSystem.makeDirectory(at: macosxFolder)

        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Sources/Target_1")))

        let resolvedDependencies = try await subject.resolveExternalDependencies(
            path: basePath.appending(components: "Tuist", ".build"),
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target_1"]),
                    ],
                    targets: [
                        .test(name: "Target_1"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ],
            packageToFolder: ["Package": basePath],
            packageToTargetsToArtifactPaths: [:],
            packageModuleAliases: [:],
            packageSettings: .test()
        )

        // Verify that only ValidFramework is included (not the one in __MACOSX)
        let validFrameworkDependency = try #require(resolvedDependencies.products["ValidFramework"])

        #expect(validFrameworkDependency.count == 1)
        let dep = try #require(validFrameworkDependency.first)
        if case let .xcframework(path, _, _, _) = dep {
            // Should not contain __MACOSX in the path
            #expect(!path.pathString.contains("__MACOSX"))
            #expect(path.pathString.contains("ValidFramework.xcframework"))
        }
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func resolveDependencies_whenArtifactsUseCustomScratchPath_mapsRemoteXcframeworks() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let packagePath = basePath.appending(component: "Tuist")
        let scratchPath = basePath.appending(component: "custom-build")
        let artifactsPath = scratchPath.appending(components: "artifacts", "tuist")

        let validXCFramework = artifactsPath.appending(components: "ValidFramework", "ValidFramework.xcframework")
        try await fileSystem.makeDirectory(at: validXCFramework)
        try await fileSystem.makeDirectory(at: packagePath)
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Sources/Target_1")))

        let resolvedDependencies = try await subject.resolveExternalDependencies(
            path: scratchPath,
            packagePath: packagePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target_1"]),
                    ],
                    targets: [
                        .test(name: "Target_1"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ],
            packageToFolder: ["Package": basePath],
            packageToTargetsToArtifactPaths: [:],
            packageModuleAliases: [:],
            packageSettings: .test()
        )

        let validFrameworkDependency = try #require(resolvedDependencies.products["ValidFramework"])
        let dep = try #require(validFrameworkDependency.first)
        if case let .xcframework(path, _, _, _) = dep {
            #expect(path.pathString.contains("custom-build/artifacts/tuist/ValidFramework/ValidFramework.xcframework"))
        }
    }

    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func resolveDependencies_whenProductContainsBinaryTargetMissingFrom_packageToTargetsToArtifactPaths() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Sources/Target_1")))
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Sources/Target_2")))
        let resolvedDependencies = try await subject.resolveExternalDependencies(
            path: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target_1", "Target_2"]),
                    ],
                    targets: [
                        .test(name: "Target_1", type: .binary, url: "https://binary.target.com"),
                        .test(name: "Target_2"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ],
            packageToFolder: ["Package": basePath],
            packageToTargetsToArtifactPaths: [:],
            packageModuleAliases: [:],
            packageSettings: .test()
        )

        #expect(
            resolvedDependencies.products ==
                [
                    "Product1": [
                        .xcframework(path: "\(basePath.pathString)/Target_1/Target_1.xcframework"),
                        .project(target: "Target_2", path: .relativeToManifest(basePath.pathString)),
                    ],
                ]
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func resolveDependencies_whenPackageIDDifferentThanName() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/Target_1")))
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/Target_2")))
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package2/Sources/Target_2")))
        let resolvedDependencies = try await subject.resolveExternalDependencies(
            path: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target_1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target_1",
                            dependencies: [
                                .product(
                                    name: "Product2",
                                    package: "Package2_different_name",
                                    moduleAliases: nil,
                                    condition: nil
                                ),
                            ]
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
                "Package2": .test(
                    name: "Package2",
                    products: [
                        .init(name: "Product2", type: .library(.automatic), targets: ["Target_2"]),
                    ],
                    targets: [
                        .test(name: "Target_2"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ],
            packageToFolder: [
                "Package": basePath.appending(component: "Package"),
                "Package2": basePath.appending(component: "Package2"),
            ],
            packageToTargetsToArtifactPaths: [:],
            packageModuleAliases: [:],
            packageSettings: .test()
        )

        #expect(
            resolvedDependencies.products ==
                [
                    "Product1": [
                        .project(
                            target: "Target_1",
                            path: .path(basePath.appending(try RelativePath(validating: "Package")).pathString),
                            condition: nil
                        ),
                    ],
                    "Product2": [
                        .project(
                            target: "Target_2",
                            path: .path(basePath.appending(try RelativePath(validating: "Package2")).pathString),
                            condition: nil
                        ),
                    ],
                ]
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func resolveDependencies_whenHasModuleAliases() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/Target_1")))
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package2/Sources/Target_2")))
        let resolvedDependencies = try await subject.resolveExternalDependencies(
            path: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product", type: .library(.automatic), targets: ["Product"]),
                    ],
                    targets: [
                        .test(
                            name: "Product",
                            dependencies: [
                                .product(
                                    name: "Product",
                                    package: "Package2",
                                    moduleAliases: ["Product": "Package2Product"],
                                    condition: nil
                                ),
                            ]
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
                "Package2": .test(
                    name: "Package2",
                    products: [
                        .init(name: "Product", type: .library(.automatic), targets: ["Product"]),
                    ],
                    targets: [
                        .test(
                            name: "Product",
                            dependencies: [
                                .target(name: "Product", condition: nil),
                            ]
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ],
            packageToFolder: [
                "Package": basePath.appending(component: "Package"),
                "Package2": basePath.appending(component: "Package2"),
            ],
            packageToTargetsToArtifactPaths: [:],
            packageModuleAliases: ["Package2": ["Product": "Package2Product"]],
            packageSettings: .test()
        )

        #expect(
            resolvedDependencies.products ==
                [
                    "Product": [
                        .project(
                            target: "Product",
                            path: .path(basePath.appending(try RelativePath(validating: "Package")).pathString),
                            condition: nil
                        ),
                    ],
                    "Package2Product": [
                        .project(
                            target: "Package2Product",
                            path: .path(basePath.appending(try RelativePath(validating: "Package2")).pathString),
                            condition: nil
                        ),
                    ],
                ]
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func resolveDependencies_whenDependencyNameContainsDot_mapsToUnderscoreInTargetName(
    ) async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/Target_1")))
        try await fileSystem
            .makeDirectory(at: basePath.appending(try RelativePath(validating: "com.example.dep-1/Sources/com.example.dep-1")))

        let resolvedDependencies = try await subject.resolveExternalDependencies(
            path: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target_1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target_1",
                            dependencies: [
                                .product(
                                    name: "com.example.dep-1",
                                    package: "com.example.dep-1",
                                    moduleAliases: nil,
                                    condition: nil
                                ),
                            ]
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
                "com.example.dep-1": .test(
                    name: "com.example.dep-1",
                    products: [
                        .init(name: "com.example.dep-1", type: .library(.automatic), targets: ["com.example.dep-1"]),
                    ],
                    targets: [
                        .test(name: "com.example.dep-1"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ],
            packageToFolder: [
                "Package": basePath.appending(component: "Package"),
                "com.example.dep-1": basePath.appending(component: "com.example.dep-1"),
            ],
            packageToTargetsToArtifactPaths: [:],
            packageModuleAliases: [:],
            packageSettings: .test()
        )

        #expect(
            resolvedDependencies.products ==
                [
                    "com.example.dep-1": [
                        .project(
                            target: "com_example_dep-1",
                            path: .path(basePath.appending(try RelativePath(validating: "com.example.dep-1")).pathString),
                            condition: nil
                        ),
                    ],
                    "Product1": [
                        .project(
                            target: "Target_1",
                            path: .path(basePath.appending(try RelativePath(validating: "Package")).pathString),
                            condition: nil
                        ),
                    ],
                ]
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func resolveDependencies_whenTargetDependenciesOnTargetHaveConditions() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/Target_1")))
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/Dependency_1")))
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/Dependency_2")))
        let resolvedDependencies = try await subject.resolveExternalDependencies(
            path: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product", type: .library(.automatic), targets: ["Target_1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target_1",
                            dependencies: [
                                .byName(name: "Dependency_1", condition: .init(platformNames: ["ios"], config: nil)),
                                .target(name: "Dependency_2", condition: .init(platformNames: ["tvos"], config: nil)),
                            ]
                        ),
                        .test(name: "Dependency_1"),
                        .test(name: "Dependency_2"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ],
            packageToFolder: [
                "Package": basePath.appending(component: "Package"),
            ],
            packageToTargetsToArtifactPaths: [:],
            packageModuleAliases: [:],
            packageSettings: .test()
        )

        #expect(
            resolvedDependencies.products ==
                [
                    "Product": [
                        .project(
                            target: "Target_1",
                            path: .path(basePath.appending(try RelativePath(validating: "Package")).pathString),
                            condition: nil
                        ),
                    ],
                ]
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func resolveDependencies_whenTargetDependenciesOnProductHaveConditions() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package_1/Sources/Target_1")))
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package_2/Sources/Target_2")))
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package_2/Sources/Target_3")))
        let resolvedDependencies = try await subject.resolveExternalDependencies(
            path: basePath,
            packageInfos: [
                "Package_1": .test(
                    name: "Package_1",
                    products: [
                        .init(name: "Product_1", type: .library(.automatic), targets: ["Target_1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target_1",
                            dependencies: [
                                .product(
                                    name: "Product_2",
                                    package: "Package_2",
                                    moduleAliases: nil,
                                    condition: .init(platformNames: ["ios"], config: nil)
                                ),
                                .product(
                                    name: "Product_3",
                                    package: "Package_2",
                                    moduleAliases: nil,
                                    condition: .init(platformNames: ["tvos"], config: nil)
                                ),
                            ]
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
                "Package_2": .test(
                    name: "Package_2",
                    products: [
                        .init(name: "Product_2", type: .library(.automatic), targets: ["Target_2"]),
                        .init(name: "Product_3", type: .library(.automatic), targets: ["Target_3"]),
                    ],
                    targets: [
                        .test(name: "Target_2"),
                        .test(name: "Target_3"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ],
            packageToFolder: [
                "Package_1": basePath.appending(component: "Package_1"),
                "Package_2": basePath.appending(component: "Package_2"),
            ],
            packageToTargetsToArtifactPaths: [:],
            packageModuleAliases: [:],
            packageSettings: .test()
        )

        #expect(
            resolvedDependencies.products ==
                [
                    "Product_1": [
                        .project(
                            target: "Target_1",
                            path: .path(basePath.appending(try RelativePath(validating: "Package_1")).pathString),
                            condition: nil
                        ),
                    ],
                    "Product_2": [
                        .project(
                            target: "Target_2",
                            path: .path(basePath.appending(try RelativePath(validating: "Package_2")).pathString),
                            condition: nil
                        ),
                    ],
                    "Product_3": [
                        .project(
                            target: "Target_3",
                            path: .path(basePath.appending(try RelativePath(validating: "Package_2")).pathString),
                            condition: nil
                        ),
                    ],
                ]
        )
    }

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func testMap() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(name: "Target1"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )

        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test("Target1", basePath: basePath),
                    ]
                )
        )
        #expect(project?.targets.first?.metadata.tags.contains(TargetTags.swiftPackage) == true)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenDynamicAndAutomaticLibraryType_mapsToStaticFramework() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                        .init(name: "Product1Dynamic", type: .library(.dynamic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(name: "Target1"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )

        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test("Target1", basePath: basePath),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenLegacySwift_usesLegacyIOSVersion() async throws {
        // Reset is needed because `Mockable` was queueing the responses, the value in `setUp` would be emitted first and then
        // this one.
        let swiftVersionProviderMock = try #require(SwiftVersionProvider.mocked)
        swiftVersionProviderMock.reset()
        given(swiftVersionProviderMock)
            .swiftVersion()
            .willReturn("5.6.0")

        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(name: "Target1"),
                    ],
                    platforms: [PackageInfo.Platform(platformName: "iOS", version: "9.0", options: [])],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )

        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            deploymentTargets: .multiplatform(
                                iOS: "9.0",
                                macOS: "10.10",
                                watchOS: "2.0",
                                tvOS: "9.0",
                                visionOS: "1.0"
                            )
                        ),
                    ]
                )
        )
    }

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func map_whenMacCatalyst() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(name: "Target1"),
                    ],
                    platforms: [.init(platformName: "maccatalyst", version: "12.0", options: [])],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )

        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            destinations: Set(Destination.allCases),
                            deploymentTargets: .multiplatform(
                                iOS: "12.0",
                                macOS: "10.13",
                                watchOS: "4.0",
                                tvOS: "12.0",
                                visionOS: "1.0"
                            )
                        ),
                    ]
                )
        )
    }

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func map_whenAlternativeDefaultSources() async throws {
        for alternativeDefaultSource in ["Source", "src", "srcs"] {
            let basePath = try #require(FileSystem.temporaryTestDirectory)
            let sourcesPath = basePath.appending(try RelativePath(validating: "Package/\(alternativeDefaultSource)/Target1"))
            try await fileSystem.makeDirectory(at: sourcesPath)

            let project = try await subject.map(
                package: "Package",
                basePath: basePath,
                packageInfos: [
                    "Package": .test(
                        name: "Package",
                        products: [
                            .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                        ],
                        targets: [
                            .test(name: "Target1"),
                        ],
                        platforms: [.ios],
                        cLanguageStandard: nil,
                        cxxLanguageStandard: nil,
                        swiftLanguageVersions: nil
                    ),
                ]
            )

            #expect(
                project ==
                    .testWithDefaultConfigs(
                        name: "Package",
                        targets: [
                            .test(
                                "Target1",
                                basePath: basePath,
                                customSources: .custom(.sourceFilesList(
                                    globs: [
                                        basePath
                                            .appending(
                                                try RelativePath(validating: "Package/\(alternativeDefaultSource)/Target1/**")
                                            )
                                            .pathString,
                                    ]
                                ))
                            ),
                        ]
                    )
            )

            try await fileSystem.remove(sourcesPath)
        }
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenOnlyBinaries_doesNotCreateProject() async throws {
        let project = try await subject.map(
            package: "Package",
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target_1"]),
                    ],
                    targets: [
                        .test(name: "Target_1", type: .binary, url: "https://binary.target.com"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )

        #expect(project == nil)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenNameContainsUnderscores_mapsToDashInBundleID() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target_1"))
        try await fileSystem.makeDirectory(at: sourcesPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target_1"]),
                    ],
                    targets: [
                        .test(name: "Target_1"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test("Target_1", basePath: basePath, customBundleID: "Target-1"),
                    ]
                )
        )
    }

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider)
    func map_whenTargetNamesDifferByUnderscores_preservesDistinctBundleIdentifiers() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let names = ["IssueReporting", "_IssueReporting", "__IssueReporting", "IssueReporting_", "Issue__Reporting"]
        for name in names {
            try await fileSystem.makeDirectory(at: basePath.appending(components: "Package", "Sources", name))
        }

        let project = try #require(try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [.init(name: "Product", type: .library(.automatic), targets: names)],
                    targets: names.map { .test(name: $0) },
                    platforms: [.ios]
                ),
            ]
        ))

        let identifiers = Dictionary(uniqueKeysWithValues: project.targets.map { ($0.name, $0.bundleId) })
        #expect(identifiers == [
            "IssueReporting": "IssueReporting",
            "_IssueReporting": "-IssueReporting",
            "__IssueReporting": "--IssueReporting",
            "IssueReporting_": "IssueReporting-",
            "Issue__Reporting": "Issue--Reporting",
        ])
        #expect(Set(identifiers.values).count == names.count)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenNameContainsPlus_sanitizesBundleID() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target+1"))
        try await fileSystem.makeDirectory(at: sourcesPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target+1"]),
                    ],
                    targets: [
                        .test(name: "Target+1"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target_1",
                            basePath: basePath,
                            customBundleID: "Target.1",
                            customSources: .custom(.sourceFilesList(globs: [
                                basePath
                                    .appending(try RelativePath(validating: "Package/Sources/Target+1/**"))
                                    .pathString,
                            ]))
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenDependencyNameContainsPlus_sanitizesDependencyReference() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath1 = basePath.appending(try RelativePath(validating: "Package/Sources/Target+1"))
        let sourcesPath2 = basePath.appending(try RelativePath(validating: "Package/Sources/Target2"))
        try await fileSystem.makeDirectory(at: sourcesPath1)
        try await fileSystem.makeDirectory(at: sourcesPath2)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target2"]),
                    ],
                    targets: [
                        .test(name: "Target+1"),
                        .test(
                            name: "Target2",
                            dependencies: [.target(name: "Target+1", condition: nil)]
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )

        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target_1",
                            basePath: basePath,
                            customBundleID: "Target.1",
                            customSources: .custom(.sourceFilesList(globs: [
                                basePath
                                    .appending(try RelativePath(validating: "Package/Sources/Target+1/**"))
                                    .pathString,
                            ]))
                        ),
                        .test(
                            "Target2",
                            basePath: basePath,
                            dependencies: [.target(name: "Target_1")]
                        ),
                    ]
                )
        )
    }

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func map_whenSettingsDefinesContainsQuotes() async throws {
        // When having a manifest that includes a GCC definition like `FOO="BAR"`, SPM successfully maintains the quotes
        // and it will convert it to a compiler parameter like `-DFOO=\"BAR\"`.
        // Xcode configuration, instead, treats the quotes as value assignment, resulting in `-DFOO=BAR`,
        // which has a different meaning in GCC macros, building packages incorrectly.
        // Tuist needs to escape those definitions for SPM manifests, as SPM is doing, so they can be built the same way.

        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1",
                            settings: [
                                .init(tool: .c, name: .define, condition: nil, value: ["FOO1=\"BAR1\""]),
                                .init(tool: .cxx, name: .define, condition: nil, value: ["FOO2=\"BAR2\""]),
                                .init(tool: .cxx, name: .define, condition: nil, value: ["FOO3=3"]),
                                .init(
                                    tool: .cxx,
                                    name: .define,
                                    condition: PackageInfo.PackageConditionDescription(
                                        platformNames: [],
                                        config: "debug"
                                    ),
                                    value: ["FOO_DEBUG=1"]
                                ),
                            ]
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            baseSettings: .settings(
                                configurations: [
                                    .debug(
                                        name: .debug,
                                        settings: [
                                            "GCC_PREPROCESSOR_DEFINITIONS": [
                                                "$(inherited)",
                                                "FOO_DEBUG=1",
                                            ],
                                        ]
                                    ),
                                    .release(
                                        name: .release,
                                        settings: [:]
                                    ),
                                ]
                            ),
                            customSettings: [
                                "GCC_PREPROCESSOR_DEFINITIONS": [
                                    "$(inherited)",
                                    // Escaped
                                    "FOO1='\"BAR1\"'",
                                    // Escaped
                                    "FOO2='\"BAR2\"'",
                                    // Not escaped
                                    "FOO3=3",
                                ],
                                "OTHER_SWIFT_FLAGS": [
                                    "$(inherited)",
                                ],
                            ]
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenNameContainsDot_mapsToUnderscoreInTargetName() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/com.example.target-1"))
        try await fileSystem.makeDirectory(at: sourcesPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "com.example.product-1", type: .library(.automatic), targets: ["com.example.target-1"]),
                    ],
                    targets: [
                        .test(name: "com.example.target-1"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )

        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "com_example_target-1",
                            basePath: basePath,
                            customProductName: "com_example_target_1",
                            customBundleID: "com.example.target-1",
                            customSources: .custom(.sourceFilesList(globs: [
                                basePath
                                    .appending(try RelativePath(validating: "Package/Sources/com.example.target-1/**"))
                                    .pathString,
                            ]))
                        ),
                    ]
                )
        )
    }

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func map_whenTargetNotInProduct_ignoresIt() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath1 = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        let sourcesPath2 = basePath.appending(try RelativePath(validating: "Package/Sources/Target2"))
        try await fileSystem.makeDirectory(at: sourcesPath1)
        try await fileSystem.makeDirectory(at: sourcesPath2)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(name: "Target1"),
                        .test(name: "Target2"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test("Target1", basePath: basePath),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenTargetIsNotRegular_ignoresTarget() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath1 = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        let sourcesPath2 = basePath.appending(try RelativePath(validating: "Package/Sources/Target2"))
        let sourcesPath3 = basePath.appending(try RelativePath(validating: "Package/Sources/Target3"))
        try await fileSystem.makeDirectory(at: sourcesPath1)
        try await fileSystem.makeDirectory(at: sourcesPath2)
        try await fileSystem.makeDirectory(at: sourcesPath3)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1", "Target2", "Target3"]),
                    ],
                    targets: [
                        .test(name: "Target1"),
                        .test(name: "Target2", type: .test),
                        .test(name: "Target3", type: .binary),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test("Target1", basePath: basePath),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenHasOpaqueAndTraversableResources_mapsCorrectly() async throws {
        // Given
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let resourcesPath = basePath.appending(
            try RelativePath(validating: "Package/Sources/Target1/Resource")
        )
        try await fileSystem.makeDirectory(at: resourcesPath)

        // Setup a normal directory that should be traversed (Base.lproj).
        try await fileSystem.makeDirectory(at: resourcesPath.appending(component: "Base.lproj"))
        try await fileSystem.touch(resourcesPath.appending(components: "Base.lproj", "Localizable.strings"))

        // Setup an opaque directory that should NOT be traversed (.xcdatamodel).
        try await fileSystem.makeDirectory(at: resourcesPath.appending(component: "Model.xcdatamodel"))
        try await fileSystem.touch(resourcesPath.appending(components: "Model.xcdatamodel", "elements"))
        try await fileSystem.touch(resourcesPath.appending(components: "Model.xcdatamodel", "layout"))

        // When
        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1",
                            resources: [
                                .init(rule: .process, path: "Resource/Base.lproj"),
                                .init(rule: .process, path: "Resource/Model.xcdatamodel"),
                            ]
                        ),
                    ],
                    platforms: [.ios]
                ),
            ]
        )

        // Then
        let expectedResources: [ProjectDescription.ResourceFileElement] = [
            .glob(
                pattern: .path(
                    basePath
                        .appending(
                            try RelativePath(
                                validating: "Package/Sources/Target1/Resource/Base.lproj/**"
                            )
                        )
                        .pathString
                ),
                excluding: [],
                tags: []
            ),
            .glob(
                pattern: .path(
                    basePath
                        .appending(
                            try RelativePath(
                                validating: "Package/Sources/Target1/Resource/Model.xcdatamodel"
                            )
                        )
                        .pathString
                ),
                excluding: [],
                tags: []
            ),
        ]

        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            resources: expectedResources
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenProductIsNotLibrary_ignoresProduct() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)

        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/Target1")))
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/Target2")))
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/Target3")))

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                        .init(name: "Product2", type: .plugin, targets: ["Target2"]),
                        .init(name: "Product3", type: .test, targets: ["Target3"]),
                    ],
                    targets: [
                        .test(name: "Target1"),
                        .test(name: "Target2"),
                        .test(name: "Target3"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test("Target1", basePath: basePath),
                    ]
                )
        )
    }

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func map_whenCustomSources() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(name: "Target1", sources: ["Subfolder", "Another/Subfolder/file.swift"]),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            customSources: .custom([
                                .init(
                                    stringLiteral:
                                    basePath.appending(try RelativePath(validating: "Package/Sources/Target1/Subfolder/**"))
                                        .pathString
                                ),
                                .init(
                                    stringLiteral:
                                    basePath
                                        .appending(
                                            try RelativePath(validating: "Package/Sources/Target1/Another/Subfolder/file.swift")
                                        )
                                        .pathString
                                ),
                            ])
                        ),
                    ]
                )
        )
    }

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func map_whenHasResources() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)

        // Create resources files and directories
        let resource1 = sourcesPath.appending(try RelativePath(validating: "Resource/Folder"))
        let resource2 = sourcesPath.appending(try RelativePath(validating: "Another/Resource/Folder"))
        let resource3 = sourcesPath.appending(try RelativePath(validating: "AnotherOne/Resource/Folder"))

        try await fileSystem.makeDirectory(at: resource1)
        try await fileSystem.makeDirectory(at: resource2)
        try await fileSystem.makeDirectory(at: resource3)

        try await fileSystem.makeDirectory(at: sourcesPath.appending(components: "Resource", "Base.lproj"))
        try await fileSystem.touch(sourcesPath.appending(components: "Resource", "Base.lproj", "Localizable.strings"))

        // Project declaration
        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1",
                            resources: [
                                .init(rule: .copy, path: "Resource/Folder"),
                                .init(rule: .process, path: "Another/Resource/Folder"),
                                .init(rule: .process, path: "AnotherOne/Resource/Folder"),
                                .init(rule: .process, path: "Resource/Base.lproj"),
                                .init(rule: .process, path: "AnotherOne/Resource/Folder/NonExisting"),
                            ],
                            exclude: [
                                "AnotherOne/Resource",
                            ]
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )

        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            customSources: .custom(.sourceFilesList(globs: [
                                .glob(
                                    .path(
                                        basePath.appending(try RelativePath(validating: "Package/Sources/Target1/**"))
                                            .pathString
                                    ),
                                    excluding: [
                                        .path(
                                            basePath
                                                .appending(
                                                    try RelativePath(validating: "Package/Sources/Target1/AnotherOne/Resource/**")
                                                )
                                                .pathString
                                        ),
                                    ]
                                ),
                            ])),
                            resources: [
                                .folderReference(
                                    path: .path(
                                        basePath
                                            .appending(try RelativePath(validating: "Package/Sources/Target1/Resource/Folder"))
                                            .pathString
                                    ),
                                    tags: []
                                ),
                                .glob(
                                    pattern: .path(
                                        basePath
                                            .appending(
                                                try RelativePath(validating: "Package/Sources/Target1/Another/Resource/Folder/**")
                                            )
                                            .pathString
                                    ),
                                    excluding: [
                                        .path(
                                            basePath
                                                .appending(
                                                    try RelativePath(validating: "Package/Sources/Target1/AnotherOne/Resource/**")
                                                )
                                                .pathString
                                        ),
                                    ],
                                    tags: []
                                ),
                                .glob(
                                    pattern: .path(
                                        basePath
                                            .appending(
                                                try RelativePath(validating: "Package/Sources/Target1/Resource/Base.lproj/**")
                                            )
                                            .pathString
                                    ),
                                    excluding: [
                                        .path(
                                            basePath
                                                .appending(
                                                    try RelativePath(validating: "Package/Sources/Target1/AnotherOne/Resource/**")
                                                )
                                                .pathString
                                        ),
                                    ],
                                    tags: []
                                ),
                            ]
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenHasAlreadyIncludedDefaultResources() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(components: "Package", "Sources", "Target1")
        let resourcesPath = sourcesPath.appending(component: "Resources")
        let defaultResourcePath = resourcesPath.appending(component: "file.xib")
        try await fileSystem.makeDirectory(at: resourcesPath)
        try await fileSystem.touch(defaultResourcePath)
        let targetTwoSourcesPath = basePath.appending(components: "Package", "Sources", "Target2")
        let targetTwoResourcesPath = targetTwoSourcesPath.appending(component: "Resources")
        let targetTwoFileXib = targetTwoResourcesPath.appending(component: "file.xib")
        try await fileSystem.makeDirectory(at: targetTwoResourcesPath)
        try await fileSystem.touch(targetTwoFileXib)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1", "Target2"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1",
                            resources: [
                                .init(rule: .process, path: "Resources"),
                            ]
                        ),
                        .test(
                            name: "Target2",
                            resources: [
                                .init(rule: .process, path: "resources/file.xib"),
                            ]
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            resources: [
                                .glob(
                                    pattern: .path(resourcesPath.appending(component: "**").pathString),
                                    excluding: [],
                                    tags: []
                                ),
                            ]
                        ),
                        .test(
                            "Target2",
                            basePath: basePath,
                            resources: [
                                .glob(
                                    pattern: .path(
                                        targetTwoSourcesPath.appending(components: "resources", "file.xib")
                                            .pathString
                                    ),
                                    excluding: [],
                                    tags: []
                                ),
                            ]
                        ),
                    ]
                )
        )
    }

    /// For more context of this scenario, see: https://github.com/tuist/tuist/issues/7445
    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func map_whenResourcesInsideXCFramework() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(components: "Package", "Sources", "Target1")
        let xcframeworkPath = sourcesPath.appending(component: "BinaryFramework.xcframework")
        let resourcePath = xcframeworkPath.appending(component: "file.xib")
        try await fileSystem.makeDirectory(at: xcframeworkPath)
        try await fileSystem.touch(resourcePath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1",
                            dependencies: [
                                .target(name: "BinaryFramework", condition: nil),
                            ]
                        ),
                        .test(
                            name: "BinaryFramework",
                            type: .binary,
                            path: "Package/Sources/Target1/BinaryFramework.xcframework"
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            resources: [],
                            dependencies: [
                                .xcframework(path: Path(stringLiteral: xcframeworkPath.pathString)),
                            ]
                        ),
                    ]
                )
        )
    }

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func map_whenHasDefaultResources() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        let defaultResourcePaths = try [
            "nib",
            "storyboard",
            "strings",
            "xcassets",
            "xcdatamodeld",
            "xcmappingmodel",
            "xib",
        ]
        .map { sourcesPath.appending(try RelativePath(validating: "Resources/file.\($0)")) }

        try await fileSystem.makeDirectory(at: sourcesPath)
        try await fileSystem.makeDirectory(at: sourcesPath.appending(component: "Resources"))
        for resourcePath in defaultResourcePaths {
            try await fileSystem.touch(resourcePath)
        }

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(name: "Target1"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            resources: defaultResourcePaths.map {
                                ResourceFileElement.glob(pattern: .path($0.pathString), excluding: [], tags: [])
                            }
                        ),
                    ]
                )
        )
    }

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func map_whenHasHeadersWithCustomModuleMap() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let headersPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1/include"))
        let moduleMapPath = headersPath.appending(component: "module.modulemap")
        let topHeaderPath = headersPath.appending(component: "AnHeader.h")
        let nestedHeaderPath = headersPath.appending(component: "Subfolder").appending(component: "AnotherHeader.h")

        try await fileSystem.makeDirectory(at: headersPath.appending(component: "Subfolder"))
        try await fileSystem.writeText("", at: moduleMapPath)
        try await fileSystem.writeText("", at: topHeaderPath)
        try await fileSystem.writeText("", at: nestedHeaderPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1"
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            headers: .spmTarget(headersPath.parentDirectory),
                            customSettings: [
                                "HEADER_SEARCH_PATHS": ["$(inherited)", "$(SRCROOT)/Sources/Target1/include"],
                                "DEFINES_MODULE": "NO",
                                "OTHER_CFLAGS": .array(["$(inherited)", "-fmodule-name=Target1"]),
                                "OTHER_SWIFT_FLAGS": [
                                    "$(inherited)",
                                ],
                            ],
                            moduleMap: "$(SRCROOT)/Sources/Target1/include/module.modulemap"
                        ),
                    ]
                )
        )
    }

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider, arguments: ["Excluded", "Vendor.1"])
    func map_whenHasHeadersWithExclude(excludedDirectory: String) async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let headersPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1/include"))
        let moduleMapPath = headersPath.appending(component: "module.modulemap")
        let headerPath = headersPath.appending(component: "AnHeader.h")
        try await fileSystem.makeDirectory(at: headersPath)
        try await fileSystem.writeText("", at: moduleMapPath)
        try await fileSystem.writeText("", at: headerPath)

        try await fileSystem.makeDirectory(at: headersPath.parentDirectory.appending(component: excludedDirectory))

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1",
                            exclude: [
                                excludedDirectory,
                            ]
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        let target = try #require(project?.targets.first)
        #expect(
            target.headers == .spmTarget(
                headersPath.parentDirectory,
                projectExcluding: [
                    .path(
                        basePath
                            .appending(try RelativePath(validating: "Package/Sources/Target1/\(excludedDirectory)/**"))
                            .pathString
                    ),
                ]
            )
        )
    }

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider)
    func map_whenExcludedDirectoryIsUnderPublicHeaders_keepsItsHeadersPublic() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let packagePath = basePath.appending(component: "Package")
        let targetPath = packagePath.appending(component: "src")
        let publicHeader = targetPath.appending(components: "realm", "geospatial.hpp")
        let vendoredHeader = targetPath.appending(components: "external", "mpark", "variant.hpp")
        let vendoredSource = targetPath.appending(components: "external", "mpark", "variant.cpp")
        try await fileSystem.makeDirectory(at: publicHeader.parentDirectory)
        try await fileSystem.makeDirectory(at: vendoredHeader.parentDirectory)
        try await fileSystem.writeText("#include <external/mpark/variant.hpp>\n", at: publicHeader)
        try await fileSystem.writeText("#pragma once\n", at: vendoredHeader)
        try await fileSystem.writeText("", at: vendoredSource)
        try await fileSystem.writeText("", at: targetPath.appending(components: "realm", "geospatial.cpp"))
        try await fileSystem.writeText("#include <realm/geospatial.hpp>\n", at: targetPath.appending(component: "realm.h"))

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "RealmCore", type: .library(.automatic), targets: ["RealmCore"]),
                    ],
                    targets: [
                        .test(
                            name: "RealmCore",
                            path: "src",
                            exclude: ["external"],
                            publicHeadersPath: ".",
                            settings: [.init(tool: .cxx, name: .headerSearchPath, condition: nil, value: ["external"])]
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )

        let target = try #require(project?.targets.first)
        let headers = try await XcodeGraph.Headers.from(
            manifest: try #require(target.headers),
            generatorPaths: GeneratorPaths(manifestDirectory: packagePath, rootDirectory: basePath),
            productName: target.productName,
            fileSystem: fileSystem
        )
        #expect(headers.public.contains(publicHeader))
        #expect(headers.public.contains(vendoredHeader))
        let sourceGlobs = try #require(target.sources?.globs)
        #expect(sourceGlobs.allSatisfy {
            $0.excluding.contains(.path(targetPath.appending(components: "external", "**").pathString))
        })
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenHasHeadersWithCustomModuleMapAndTargetWithDashes() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let headersPath = basePath.appending(try RelativePath(validating: "Package/Sources/target-with-dashes/include"))
        let moduleMapPath = headersPath.appending(component: "module.modulemap")
        let headerPath = headersPath.appending(component: "AnHeader.h")
        try await fileSystem.makeDirectory(at: headersPath)
        try await fileSystem.writeText("", at: moduleMapPath)
        try await fileSystem.writeText("", at: headerPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "target-with-dashes", type: .library(.automatic), targets: ["target-with-dashes"]),
                    ],
                    targets: [
                        .test(
                            name: "target-with-dashes"
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "target-with-dashes",
                            basePath: basePath,
                            customProductName: "target_with_dashes",
                            headers: .spmTarget(headersPath.parentDirectory),
                            customSettings: [
                                "HEADER_SEARCH_PATHS": ["$(inherited)", "$(SRCROOT)/Sources/target-with-dashes/include"],
                                "DEFINES_MODULE": "NO",
                                "OTHER_CFLAGS": .array(["$(inherited)", "-fmodule-name=target_with_dashes"]),
                                "OTHER_SWIFT_FLAGS": [
                                    "$(inherited)",
                                ],
                            ],
                            moduleMap: "$(SRCROOT)/Sources/target-with-dashes/include/module.modulemap"
                        ),
                    ]
                )
        )
    }

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func map_whenHasSystemLibrary() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let targetPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        let moduleMapPath = targetPath.appending(component: "module.modulemap")
        try await fileSystem.makeDirectory(at: targetPath)
        try await fileSystem.writeText("", at: moduleMapPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1",
                            type: .system
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )

        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            customSources: .custom(nil),
                            customSettings: [
                                "DEFINES_MODULE": "NO",
                                "OTHER_CFLAGS": .array(["$(inherited)", "-fmodule-name=Target1"]),
                                "OTHER_SWIFT_FLAGS": [
                                    "$(inherited)",
                                ],
                            ],
                            moduleMap: "$(SRCROOT)/Sources/Target1/module.modulemap"
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_errorWhenSystemLibraryHasMissingModuleMap() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let targetPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        let moduleMapPath = targetPath.appending(component: "module.modulemap")
        try await fileSystem.makeDirectory(at: targetPath)

        let error = PackageInfoMapperError.modulemapMissing(
            moduleMapPath: moduleMapPath.pathString,
            package: "Package",
            target: "Target1"
        )

        await #expect(throws: error, performing: {
            try await subject.map(
                package: "Package",
                basePath: basePath,
                packageInfos: [
                    "Package": .test(
                        name: "Package",
                        products: [
                            .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                        ],
                        targets: [
                            .test(
                                name: "Target1",
                                type: .system
                            ),
                        ],
                        platforms: [.ios],
                        cLanguageStandard: nil,
                        cxxLanguageStandard: nil,
                        swiftLanguageVersions: nil
                    ),
                ]
            )
        })
    }

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func map_whenHasHeadersWithUmbrellaHeader() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let headersPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1/include"))
        let topHeaderPath = headersPath.appending(component: "Target1.h")
        let nestedHeaderPath = headersPath.appending(component: "Subfolder").appending(component: "AnHeader.h")

        try await fileSystem.makeDirectory(at: headersPath.appending(component: "Subfolder"))
        try await fileSystem.writeText("", at: topHeaderPath)
        try await fileSystem.writeText("", at: nestedHeaderPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1"
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            headers: .spmTarget(
                                headersPath.parentDirectory,
                                moduleMap: basePath.appending(components: "Package", "Derived", "Target1.modulemap")
                            ),
                            customSettings: [
                                "HEADER_SEARCH_PATHS": ["$(inherited)", "$(SRCROOT)/Sources/Target1/include"],
                                "MODULEMAP_FILE": .string("$(SRCROOT)/Derived/Target1.modulemap"),
                                "DEFINES_MODULE": "NO",
                                "OTHER_CFLAGS": .array(["$(inherited)", "-fmodule-name=Target1"]),
                                "OTHER_SWIFT_FLAGS": [
                                    "$(inherited)",
                                ],
                            ]
                        ),
                    ]
                )
        )
    }

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func map_whenDependenciesHaveHeaders() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let target1HeadersPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1/include"))
        let target1ModuleMapPath = target1HeadersPath.appending(component: "module.modulemap")
        let dependency1HeadersPath = basePath.appending(try RelativePath(validating: "Package/Sources/Dependency1/include"))
        let dependency1ModuleMapPath = dependency1HeadersPath.appending(component: "module.modulemap")
        let dependency2HeadersPath = basePath.appending(try RelativePath(validating: "Package/Sources/Dependency2/include"))
        let dependency2ModuleMapPath = dependency2HeadersPath.appending(component: "module.modulemap")

        try await fileSystem.makeDirectory(at: target1HeadersPath.appending(component: "Subfolder"))
        try await fileSystem.writeText("", at: target1ModuleMapPath)
        try await fileSystem.makeDirectory(at: dependency1HeadersPath.appending(component: "Subfolder"))
        try await fileSystem.writeText("", at: dependency1ModuleMapPath)
        try await fileSystem.makeDirectory(at: dependency2HeadersPath.appending(component: "Subfolder"))
        try await fileSystem.writeText("", at: dependency2ModuleMapPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1",
                            dependencies: [.target(name: "Dependency1", condition: nil)]
                        ),
                        .test(
                            name: "Dependency1",
                            dependencies: [.target(name: "Dependency2", condition: nil)]
                        ),
                        .test(name: "Dependency2"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            headers: .spmTarget(target1HeadersPath.parentDirectory),
                            dependencies: [.target(name: "Dependency1")],
                            customSettings: [
                                "HEADER_SEARCH_PATHS": [
                                    "$(inherited)",
                                    "$(SRCROOT)/Sources/Target1/include",
                                ],
                                "DEFINES_MODULE": "NO",
                                "OTHER_CFLAGS": .array(["$(inherited)", "-fmodule-name=Target1"]),
                                "OTHER_SWIFT_FLAGS": [
                                    "$(inherited)",
                                ],
                            ],
                            moduleMap: "$(SRCROOT)/Sources/Target1/include/module.modulemap"
                        ),
                        .test(
                            "Dependency1",
                            basePath: basePath,
                            headers: .spmTarget(dependency1HeadersPath.parentDirectory),
                            dependencies: [.target(name: "Dependency2")],
                            customSettings: [
                                "HEADER_SEARCH_PATHS": [
                                    "$(inherited)",
                                    "$(SRCROOT)/Sources/Dependency1/include",
                                ],
                                "DEFINES_MODULE": "NO",
                                "OTHER_CFLAGS": .array(["$(inherited)", "-fmodule-name=Dependency1"]),
                                "OTHER_SWIFT_FLAGS": [
                                    "$(inherited)",
                                ],
                            ],
                            moduleMap: "$(SRCROOT)/Sources/Dependency1/include/module.modulemap"
                        ),
                        .test(
                            "Dependency2",
                            basePath: basePath,
                            headers: .spmTarget(dependency2HeadersPath.parentDirectory),
                            customSettings: [
                                "HEADER_SEARCH_PATHS": [
                                    "$(inherited)",
                                    "$(SRCROOT)/Sources/Dependency2/include",
                                ],
                                "DEFINES_MODULE": "NO",
                                "OTHER_CFLAGS": .array(["$(inherited)", "-fmodule-name=Dependency2"]),
                                "OTHER_SWIFT_FLAGS": [
                                    "$(inherited)",
                                ],
                            ],
                            moduleMap: "$(SRCROOT)/Sources/Dependency2/include/module.modulemap"
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenExternalDependenciesHaveHeaders() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let target1HeadersPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1/include"))
        let target1ModuleMapPath = target1HeadersPath.appending(component: "module.modulemap")
        let dependency1HeadersPath = basePath.appending(try RelativePath(validating: "Package2/Sources/Dependency1/include"))
        let dependency1ModuleMapPath = dependency1HeadersPath.appending(component: "module.modulemap")
        let dependency2HeadersPath = basePath.appending(try RelativePath(validating: "Package3/Sources/Dependency2/include"))
        let dependency2ModuleMapPath = dependency2HeadersPath.appending(component: "module.modulemap")

        try await fileSystem.makeDirectory(at: target1HeadersPath.appending(component: "Subfolder"))
        try await fileSystem.writeText("", at: target1ModuleMapPath)
        try await fileSystem.makeDirectory(at: dependency1HeadersPath.appending(component: "Subfolder"))
        try await fileSystem.writeText("", at: dependency1ModuleMapPath)
        try await fileSystem.makeDirectory(at: dependency2HeadersPath.appending(component: "Subfolder"))
        try await fileSystem.writeText("", at: dependency2ModuleMapPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1",
                            dependencies: [.product(name: "Dependency1", package: "Package2", moduleAliases: nil, condition: nil)]
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
                "Package2": .test(
                    name: "Package2",
                    products: [
                        .init(name: "Dependency1", type: .library(.automatic), targets: ["Dependency1"]),
                    ],
                    targets: [
                        .test(
                            name: "Dependency1",
                            dependencies: [.product(name: "Dependency2", package: "Package3", moduleAliases: nil, condition: nil)]
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
                "Package3": .test(
                    name: "Package3",
                    products: [
                        .init(name: "Dependency2", type: .library(.automatic), targets: ["Dependency2"]),
                    ],
                    targets: [
                        .test(
                            name: "Dependency2"
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            headers: .spmTarget(target1HeadersPath.parentDirectory),
                            dependencies: [.external(name: "Dependency1", condition: nil)],
                            customSettings: [
                                "HEADER_SEARCH_PATHS": [
                                    "$(inherited)",
                                    "$(SRCROOT)/Sources/Target1/include",
                                ],
                                "DEFINES_MODULE": "NO",
                                "OTHER_CFLAGS": .array(["$(inherited)", "-fmodule-name=Target1"]),
                                "OTHER_SWIFT_FLAGS": [
                                    "$(inherited)",
                                ],
                            ],
                            moduleMap: "$(SRCROOT)/Sources/Target1/include/module.modulemap"
                        ),
                    ]
                )
        )
    }

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func map_whenCustomPath() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)

        // Create resources files and directories
        let headersPath = basePath.appending(try RelativePath(validating: "Package/Custom/Headers"))
        let headerPath = headersPath.appending(component: "module.h")
        let moduleMapPath = headersPath.appending(component: "module.modulemap")

        try await fileSystem.makeDirectory(at: headersPath)
        try await fileSystem.writeText("", at: headerPath)
        try await fileSystem.writeText("", at: moduleMapPath)

        let resourceFolderPathCustomTarget = basePath.appending(try RelativePath(validating: "Package/Custom/Resource/Folder"))
        try await fileSystem.makeDirectory(at: resourceFolderPathCustomTarget)

        // Project declaration
        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1",
                            path: "Custom",
                            sources: ["Sources/Folder"],
                            resources: [.init(rule: .copy, path: "Resource/Folder")],
                            publicHeadersPath: "Headers"
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )

        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            customSources: .custom(.sourceFilesList(globs: [
                                basePath
                                    .appending(try RelativePath(validating: "Package/Custom/Sources/Folder/**")).pathString,
                            ])),
                            resources: [
                                .folderReference(
                                    path: .path(
                                        basePath.appending(try RelativePath(validating: "Package/Custom/Resource/Folder"))
                                            .pathString
                                    ),
                                    tags: []
                                ),
                            ],
                            headers: .spmTarget(headersPath.parentDirectory, publicDirectory: "Headers", moduleName: "Target1"),
                            customSettings: [
                                "HEADER_SEARCH_PATHS": ["$(inherited)", "$(SRCROOT)/Custom/Headers"],
                                "DEFINES_MODULE": "NO",
                                "OTHER_CFLAGS": .array(["$(inherited)", "-fmodule-name=Target1"]),
                                "OTHER_SWIFT_FLAGS": [
                                    "$(inherited)",
                                ],
                            ],
                            moduleMap: "$(SRCROOT)/Custom/Headers/module.modulemap"
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenPublicHeaderImportsSamePackageModule_addsTargetDependency() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let firebaseCoreHeadersPath = basePath
            .appending(try RelativePath(validating: "Package/Sources/FirebaseCore/Public/FirebaseCore"))
        let firebaseCoreExtensionHeadersPath = basePath
            .appending(try RelativePath(validating: "Package/Sources/FirebaseCore/Extension"))

        try await fileSystem.makeDirectory(at: firebaseCoreHeadersPath)
        try await fileSystem.makeDirectory(at: firebaseCoreExtensionHeadersPath)
        try await fileSystem.writeText("", at: firebaseCoreHeadersPath.appending(component: "FIRApp.h"))
        try await fileSystem.writeText(
            """
            #import <FirebaseCore/FIRApp.h>
            """,
            at: firebaseCoreExtensionHeadersPath.appending(component: "FirebaseCoreInternal.h")
        )

        let project = try #require(
            try await subject.map(
                package: "Package",
                basePath: basePath,
                packageInfos: [
                    "Package": .test(
                        name: "Package",
                        products: [
                            .init(name: "FirebaseCore", type: .library(.automatic), targets: ["FirebaseCore"]),
                            .init(
                                name: "FirebaseCoreExtension",
                                type: .library(.automatic),
                                targets: ["FirebaseCoreExtension"]
                            ),
                        ],
                        targets: [
                            .test(
                                name: "FirebaseCore",
                                path: "Sources/FirebaseCore",
                                publicHeadersPath: "Public"
                            ),
                            .test(
                                name: "FirebaseCoreExtension",
                                path: "Sources/FirebaseCore/Extension",
                                publicHeadersPath: "."
                            ),
                        ],
                        platforms: [.ios],
                        cLanguageStandard: nil,
                        cxxLanguageStandard: nil,
                        swiftLanguageVersions: nil
                    ),
                ]
            )
        )

        let firebaseCoreExtensionTarget = try #require(
            project.targets.first(where: { $0.name == "FirebaseCoreExtension" })
        )
        #expect(
            firebaseCoreExtensionTarget.dependencies.contains(
                ProjectDescription.TargetDependency.target(name: "FirebaseCore")
            )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenDependencyHasHeaders_addsThemToHeaderSearchPath() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let dependencyHeadersPath = basePath.appending(try RelativePath(validating: "Package/Sources/Dependency1/include"))
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))

        try await fileSystem.makeDirectory(at: dependencyHeadersPath)
        try await fileSystem.touch(dependencyHeadersPath.appending(component: "Header.h"))
        try await fileSystem.makeDirectory(at: sourcesPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1",
                            dependencies: [.target(name: "Dependency1", condition: nil)]
                        ),
                        .test(name: "Dependency1"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            dependencies: [.target(name: "Dependency1")]
                        ),
                        .test(
                            "Dependency1",
                            basePath: basePath,
                            headers: .spmTarget(
                                dependencyHeadersPath.parentDirectory,
                                moduleMap: basePath.appending(components: "Package", "Derived", "Dependency1.modulemap"),
                                directoryModule: true
                            ),
                            customSettings: [
                                "HEADER_SEARCH_PATHS": ["$(inherited)", "$(SRCROOT)/Sources/Dependency1/include"],
                                "DEFINES_MODULE": "NO",
                                "OTHER_CFLAGS": .array(["$(inherited)", "-fmodule-name=Dependency1"]),
                                "OTHER_SWIFT_FLAGS": [
                                    "$(inherited)",
                                ],
                            ],
                            moduleMap: "$(SRCROOT)/Derived/Dependency1.modulemap"
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenDirectoryPublicHeadersHaveDuplicateBasenames_preservesSourceLayout() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let packagePath = basePath.appending(component: "Package")
        let publicHeadersPath = packagePath.appending(component: "spm_headers")
        let nestedPublicHeadersPath = publicHeadersPath.appending(component: "nanopb")

        try await fileSystem.makeDirectory(at: nestedPublicHeadersPath)
        try await fileSystem.writeText("", at: packagePath.appending(component: "pb.h"))
        try await fileSystem.writeText("", at: packagePath.appending(component: "pb_common.h"))
        try await fileSystem.writeText("", at: packagePath.appending(component: "pb_common.c"))
        try await fileSystem.writeText(#"#include "nanopb/pb.h""#, at: publicHeadersPath.appending(component: "pb.h"))
        try await fileSystem.writeText(
            #"#include "nanopb/pb_common.h""#,
            at: publicHeadersPath.appending(component: "pb_common.h")
        )
        try await fileSystem.writeText("", at: nestedPublicHeadersPath.appending(component: "pb.h"))
        try await fileSystem.writeText("", at: nestedPublicHeadersPath.appending(component: "pb_common.h"))

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "nanopb", type: .library(.automatic), targets: ["nanopb"]),
                    ],
                    targets: [
                        .test(
                            name: "nanopb",
                            path: ".",
                            sources: [
                                "pb.h",
                                "pb_common.h",
                                "pb_common.c",
                            ],
                            publicHeadersPath: "spm_headers"
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )

        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "nanopb",
                            basePath: basePath,
                            customSources: .custom(.sourceFilesList(globs: [
                                packagePath.appending(component: "pb.h").pathString,
                                packagePath.appending(component: "pb_common.h").pathString,
                                packagePath.appending(component: "pb_common.c").pathString,
                            ])),
                            headers: .spmTarget(
                                packagePath,
                                publicDirectory: "spm_headers",
                                moduleName: "nanopb",
                                moduleMap: packagePath.appending(components: "Derived", "nanopb.modulemap"),
                                directoryModule: true
                            ),
                            customSettings: [
                                "HEADER_SEARCH_PATHS": ["$(inherited)", "$(SRCROOT)/spm_headers"],
                                "DEFINES_MODULE": "NO",
                                "OTHER_CFLAGS": .array(["$(inherited)", "-fmodule-name=nanopb"]),
                                "OTHER_SWIFT_FLAGS": [
                                    "$(inherited)",
                                ],
                            ],
                            moduleMap: "$(SRCROOT)/Derived/nanopb.modulemap"
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenMultipleAvailable_takesMultiple() async throws {
        // Given
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)

        // When
        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(name: "Target1"),
                    ],
                    platforms: [.ios, .tvos],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )

        // Then
        let expected: ProjectDescription.Project = .testWithDefaultConfigs(
            name: "Package",
            targets: [
                .test(
                    "Target1",
                    basePath: basePath,
                    customProductName: "Target1",
                    customBundleID: "Target1",
                    customSources: .custom(.sourceFilesList(globs: [
                        basePath.appending(try RelativePath(validating: "Package/Sources/Target1/**"))
                            .pathString,
                    ]))
                ),
            ]
        )

        #expect(project?.name == expected.name)

        // Need to sort targets of projects, because internally a set is used to generate targets for different platforms
        // That could lead to mixed orders
        let projectTargets = project?.targets.sorted(by: \.name)
        let expectedTargets = expected.targets.sorted(by: \.name)
        #expect(projectTargets == expectedTargets)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenPackageDefinesPlatform_configuresDeploymentTarget() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)
        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(name: "Target1"),
                    ],
                    platforms: [.init(platformName: "ios", version: "13.0", options: [])],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )

        let other = ProjectDescription.Project.testWithDefaultConfigs(
            name: "Package",
            targets: [
                .test(
                    "Target1",
                    basePath: basePath,
                    deploymentTargets: .multiplatform(
                        iOS: "13.0",
                        macOS: "10.13",
                        watchOS: "4.0",
                        tvOS: "12.0",
                        visionOS: "1.0"
                    )
                ),
            ]
        )

        #expect(
            project ==
                other
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenSDKMinimumsAreUnavailable_clampsPackageDeploymentTargetsToSwiftVersionMinimums() async throws {
        let swiftVersionProviderMock = try #require(SwiftVersionProvider.mocked)
        swiftVersionProviderMock.reset()
        given(swiftVersionProviderMock)
            .swiftVersion()
            .willReturn("6.4")

        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(name: "Target1"),
                    ],
                    platforms: [
                        .init(platformName: "ios", version: "9.0", options: []),
                        .init(platformName: "macos", version: "10.10", options: []),
                        .init(platformName: "watchos", version: "2.0", options: []),
                        .init(platformName: "tvos", version: "9.0", options: []),
                    ],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )

        let target = try #require(project?.targets.first)
        #expect(
            target.deploymentTargets == .multiplatform(
                iOS: "15.0",
                macOS: "12.0",
                watchOS: "9.0",
                tvOS: "15.0",
                visionOS: "1.0"
            )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenPackageDeploymentTargetsAreOlderThanTheSDKs_clampsThemToTheSDKMinimums() async throws {
        let sdkDeploymentTargetsProviderMock = try #require(SDKDeploymentTargetsProvider.mocked)
        sdkDeploymentTargetsProviderMock.reset()
        given(sdkDeploymentTargetsProviderMock)
            .minimumDeploymentTargets()
            .willReturn(
                SDKDeploymentTargets(iOS: "15.0", macOS: "12.0", watchOS: "9.0", tvOS: "15.0", visionOS: "1.0")
            )

        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(name: "Target1"),
                    ],
                    platforms: [
                        .init(platformName: "ios", version: "9.0", options: []),
                        .init(platformName: "macos", version: "10.15", options: []),
                        .init(platformName: "watchos", version: "2.0", options: []),
                        .init(platformName: "tvos", version: "9.0", options: []),
                    ],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )

        let target = try #require(project?.targets.first)
        #expect(
            target.deploymentTargets == .multiplatform(
                iOS: "15.0",
                macOS: "12.0",
                watchOS: "9.0",
                tvOS: "15.0",
                visionOS: "1.0"
            )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenPackageDeploymentTargetsAreSupportedByTheSDKs_keepsThem() async throws {
        let swiftVersionProviderMock = try #require(SwiftVersionProvider.mocked)
        swiftVersionProviderMock.reset()
        given(swiftVersionProviderMock)
            .swiftVersion()
            .willReturn("6.3")
        let sdkDeploymentTargetsProviderMock = try #require(SDKDeploymentTargetsProvider.mocked)
        sdkDeploymentTargetsProviderMock.reset()
        given(sdkDeploymentTargetsProviderMock)
            .minimumDeploymentTargets()
            .willReturn(
                SDKDeploymentTargets(iOS: "12.0", macOS: "10.13", watchOS: "4.0", tvOS: "12.0", visionOS: "1.0")
            )

        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(name: "Target1"),
                    ],
                    platforms: [
                        .init(platformName: "ios", version: "14.0", options: []),
                        .init(platformName: "macos", version: "10.15", options: []),
                        .init(platformName: "watchos", version: "7.0", options: []),
                        .init(platformName: "tvos", version: "14.0", options: []),
                    ],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )

        let target = try #require(project?.targets.first)
        #expect(
            target.deploymentTargets == .multiplatform(
                iOS: "14.0",
                macOS: "10.15",
                watchOS: "7.0",
                tvOS: "14.0",
                visionOS: "1.0"
            )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenTargetBuildsForMacCatalyst_clampsIOSToTheCatalystSDKMinimum() async throws {
        let sdkDeploymentTargetsProviderMock = try #require(SDKDeploymentTargetsProvider.mocked)
        sdkDeploymentTargetsProviderMock.reset()
        given(sdkDeploymentTargetsProviderMock)
            .minimumDeploymentTargets()
            .willReturn(
                SDKDeploymentTargets(
                    iOS: "12.0",
                    macOS: "10.13",
                    watchOS: "4.0",
                    tvOS: "12.0",
                    visionOS: "1.0",
                    macCatalyst: "13.1"
                )
            )

        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(name: "Target1"),
                    ],
                    platforms: [
                        .init(platformName: "ios", version: "12.0", options: []),
                    ],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )

        let target = try #require(project?.targets.first)
        #expect(target.destinations.contains(ProjectDescription.Destination.macCatalyst))
        #expect(target.deploymentTargets?.iOS == "13.1")
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenTargetDoesNotBuildForMacCatalyst_keepsTheIOSSDKMinimum() async throws {
        let sdkDeploymentTargetsProviderMock = try #require(SDKDeploymentTargetsProvider.mocked)
        sdkDeploymentTargetsProviderMock.reset()
        given(sdkDeploymentTargetsProviderMock)
            .minimumDeploymentTargets()
            .willReturn(
                SDKDeploymentTargets(
                    iOS: "12.0",
                    macOS: "10.13",
                    watchOS: "4.0",
                    tvOS: "12.0",
                    visionOS: "1.0",
                    macCatalyst: "13.1"
                )
            )

        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageType: .local,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(name: "Target1"),
                    ],
                    platforms: [
                        .init(platformName: "ios", version: "12.0", options: []),
                    ],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ],
            packageSettings: .test(
                productDestinations: ["Product1": [.iPhone, .iPad]],
                baseSettings: .default
            )
        )

        let target = try #require(project?.targets.first)
        #expect(!target.destinations.contains(ProjectDescription.Destination.macCatalyst))
        #expect(target.deploymentTargets?.iOS == "12.0")
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenOnlySomeSDKMinimumsAreAvailable_fallsBackToSwiftVersionMinimumsForTheRest() async throws {
        let swiftVersionProviderMock = try #require(SwiftVersionProvider.mocked)
        swiftVersionProviderMock.reset()
        given(swiftVersionProviderMock)
            .swiftVersion()
            .willReturn("6.4")
        let sdkDeploymentTargetsProviderMock = try #require(SDKDeploymentTargetsProvider.mocked)
        sdkDeploymentTargetsProviderMock.reset()
        given(sdkDeploymentTargetsProviderMock)
            .minimumDeploymentTargets()
            .willReturn(SDKDeploymentTargets(macOS: "12.0"))

        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(name: "Target1"),
                    ],
                    platforms: [
                        .init(platformName: "ios", version: "9.0", options: []),
                        .init(platformName: "macos", version: "10.10", options: []),
                        .init(platformName: "watchos", version: "2.0", options: []),
                        .init(platformName: "tvos", version: "9.0", options: []),
                    ],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )

        let target = try #require(project?.targets.first)
        #expect(
            target.deploymentTargets == .multiplatform(
                iOS: "15.0",
                macOS: "12.0",
                watchOS: "9.0",
                tvOS: "15.0",
                visionOS: "1.0"
            )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenSettingsContainsCHeaderSearchPath_mapsToHeaderSearchPathsSetting() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)
        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1",
                            settings: [
                                .init(tool: .c, name: .headerSearchPath, condition: nil, value: ["value"]),
                                .init(
                                    tool: .c,
                                    name: .headerSearchPath,
                                    condition: nil,
                                    value: ["White Space Folder/value"]
                                ),
                            ]
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            customSettings: [
                                "HEADER_SEARCH_PATHS": [
                                    "$(inherited)",
                                    "$(SRCROOT)/Sources/Target1/value",
                                    "\"$(SRCROOT)/Sources/Target1/White Space Folder/value\"",
                                ],
                                "OTHER_SWIFT_FLAGS": [
                                    "$(inherited)",
                                ],
                            ]
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenSettingsContainsCXXHeaderSearchPath_mapsToHeaderSearchPathsSetting(
    ) async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)
        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1",
                            settings: [.init(tool: .cxx, name: .headerSearchPath, condition: nil, value: ["value"])]
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            customSettings: [
                                "HEADER_SEARCH_PATHS": [
                                    "$(inherited)",
                                    "$(SRCROOT)/Sources/Target1/value",
                                ],
                                "OTHER_SWIFT_FLAGS": [
                                    "$(inherited)",
                                ],
                            ]
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenSettingsContainsCDefine_mapsToGccPreprocessorDefinitions() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)
        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1",
                            settings: [
                                .init(tool: .c, name: .define, condition: nil, value: ["key1"]),
                                .init(tool: .c, name: .define, condition: nil, value: ["key2=value"]),
                                .init(tool: .c, name: .define, condition: nil, value: ["key3="]),
                            ]
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            customSettings: [
                                "GCC_PREPROCESSOR_DEFINITIONS": ["$(inherited)", "key1=1", "key2=value", "key3="],
                                "OTHER_SWIFT_FLAGS": [
                                    "$(inherited)",
                                ],
                            ]
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenSettingsContainsCXXDefine_mapsToGccPreprocessorDefinitions() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)
        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1",
                            settings: [
                                .init(tool: .cxx, name: .define, condition: nil, value: ["key1"]),
                                .init(tool: .cxx, name: .define, condition: nil, value: ["key2=value"]),
                            ]
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            customSettings: [
                                "GCC_PREPROCESSOR_DEFINITIONS": ["$(inherited)", "key1=1", "key2=value"],
                                "OTHER_SWIFT_FLAGS": [
                                    "$(inherited)",
                                ],
                            ]
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenSettingsContainsSwiftDefine_mapsToSwiftActiveCompilationConditions(
    ) async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)
        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1",
                            settings: [
                                .init(tool: .swift, name: .define, condition: nil, value: ["key"]),
                            ]
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            customSettings: [
                                "SWIFT_ACTIVE_COMPILATION_CONDITIONS": ["$(inherited)", "key"],
                                "OTHER_SWIFT_FLAGS": [
                                    "$(inherited)",
                                ],
                            ]
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenSettingsContainsCUnsafeFlags_mapsToOtherCFlags() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)
        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1",
                            settings: [
                                .init(tool: .c, name: .unsafeFlags, condition: nil, value: ["key1"]),
                                .init(tool: .c, name: .unsafeFlags, condition: nil, value: ["key2", "key3"]),
                            ]
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            customSettings: [
                                "OTHER_CFLAGS": ["$(inherited)", "key1", "key2", "key3"],
                                "OTHER_SWIFT_FLAGS": [
                                    "$(inherited)",
                                ],
                            ]
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenSettingsContainsCXXUnsafeFlags_mapsToOtherCPlusPlusFlags() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)
        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1",
                            settings: [
                                .init(tool: .cxx, name: .unsafeFlags, condition: nil, value: ["key1"]),
                                .init(tool: .cxx, name: .unsafeFlags, condition: nil, value: ["key2", "key3"]),
                            ]
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            customSettings: [
                                "OTHER_CPLUSPLUSFLAGS": ["$(inherited)", "key1", "key2", "key3"],
                                "OTHER_SWIFT_FLAGS": [
                                    "$(inherited)",
                                ],
                            ]
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenSettingsContainsSwiftUnsafeFlags_mapsToOtherSwiftFlags() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)
        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1",
                            settings: [
                                .init(tool: .swift, name: .unsafeFlags, condition: nil, value: ["key1"]),
                                .init(tool: .swift, name: .unsafeFlags, condition: nil, value: ["key2", "key3"]),
                            ]
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            customSettings: ["OTHER_SWIFT_FLAGS": ["$(inherited)", "key1", "key2", "key3"]]
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenSettingsContainsEnableUpcomingFeature_mapsToOtherSwiftFlags() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)
        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1",
                            settings: [
                                .init(tool: .swift, name: .enableUpcomingFeature, condition: nil, value: ["Foo"]),
                            ]
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            customSettings: ["OTHER_SWIFT_FLAGS": ["$(inherited)", "-enable-upcoming-feature \"Foo\""]]
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenSettingsContainsEnableExperimentalFeature_mapsToOtherSwiftFlags() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)
        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1",
                            settings: [
                                .init(tool: .swift, name: .enableExperimentalFeature, condition: nil, value: ["Foo"]),
                            ]
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            customSettings: ["OTHER_SWIFT_FLAGS": ["$(inherited)", "-enable-experimental-feature \"Foo\""]]
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenSettingsContainsSwiftLanguageMode_mapsToSwiftVersion() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)
        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1",
                            settings: [
                                .init(tool: .swift, name: .swiftLanguageMode, condition: nil, value: ["5"]),
                            ]
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            customSettings: [
                                "OTHER_SWIFT_FLAGS": ["$(inherited)"],
                                "SWIFT_VERSION": "5",
                            ]
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenSettingsContainsLinkerUnsafeFlags_mapsToOtherLdFlags() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1",
                            settings: [
                                .init(tool: .linker, name: .unsafeFlags, condition: nil, value: ["key1"]),
                                .init(tool: .linker, name: .unsafeFlags, condition: nil, value: ["key2", "key3"]),
                            ]
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            customSettings: [
                                "OTHER_LDFLAGS": ["$(inherited)", "key1", "key2", "key3"],
                                "OTHER_SWIFT_FLAGS": [
                                    "$(inherited)",
                                ],
                            ]
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenConfigurationContainsBaseSettingsDictionary_usesBaseSettings() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageType: .local,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1",
                            settings: [
                                .init(tool: .linker, name: .unsafeFlags, condition: nil, value: ["key1"]),
                                .init(tool: .linker, name: .unsafeFlags, condition: nil, value: ["key2", "key3"]),
                            ]
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ],
            packageSettings: .test(
                productDestinations: [
                    "Product1": .iOS,
                ],
                baseSettings: .init(
                    base: [
                        "EXCLUDED_ARCHS[sdk=iphonesimulator*]": .string("x86_64"),
                    ],
                    configurations: [
                        .init(name: "Debug", variant: .debug): .init(
                            settings: ["CUSTOM_SETTING_1": .string("CUSTOM_VALUE_1")],
                            xcconfig: sourcesPath.appending(component: "Config.xcconfig")
                        ),
                        .init(name: "Release", variant: .release): .init(
                            settings: ["CUSTOM_SETTING_2": .string("CUSTOM_VALUE_2")],
                            xcconfig: sourcesPath.appending(component: "Config.xcconfig")
                        ),
                    ]
                )
            )
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    options: .options(
                        automaticSchemesOptions: .enabled(),
                        disableBundleAccessors: false,
                        disableSynthesizedResourceAccessors: true,
                        textSettings: .textSettings(usesTabs: nil, indentWidth: nil, tabWidth: nil, wrapsLines: nil)
                    ),
                    settings: .settings(
                        base: [
                            "EXCLUDED_ARCHS[sdk=iphonesimulator*]": .string("x86_64"),
                            "SWIFT_VERSION": "5",
                        ],
                        configurations: [
                            .debug(
                                name: "Debug",
                                settings: ["CUSTOM_SETTING_1": .string("CUSTOM_VALUE_1")],
                                xcconfig: "Sources/Target1/Config.xcconfig"
                            ),
                            .release(
                                name: "Release",
                                settings: ["CUSTOM_SETTING_2": .string("CUSTOM_VALUE_2")],
                                xcconfig: "Sources/Target1/Config.xcconfig"
                            ),
                        ],
                        defaultSettings: .recommended
                    ),
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            destinations: .iOS,
                            deploymentTargets: .iOS("12.0"),
                            customSettings: [
                                "EXCLUDED_ARCHS[sdk=iphonesimulator*]": .string("x86_64"),
                                "OTHER_LDFLAGS": ["$(inherited)", "key1", "key2", "key3"],
                                "OTHER_SWIFT_FLAGS": [
                                    "$(inherited)",
                                ],
                            ]
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenConfigurationContainsTargetSettingsDictionary_mapsToCustomSettings(
    ) async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)

        let customSettings: XcodeGraph.Settings = .test(
            base: ["CUSTOM_SETTING": .string("CUSTOM_VALUE")],
            configurations: [
                .init(name: "Custom Debug", variant: .debug): .init(
                    settings: [
                        "CUSTOM_SETTING_1": .string("CUSTOM_VALUE_1"),
                        "OTHER_SWIFT_FLAGS": .array(["-DDEBUG"]),
                    ],
                    xcconfig: sourcesPath.appending(component: "Config.xcconfig")
                ),
                .init(name: "Custom Release", variant: .release): .init(
                    settings: ["CUSTOM_SETTING_3": .string("CUSTOM_VALUE_4")],
                    xcconfig: sourcesPath.appending(component: "Config.xcconfig")
                ),
            ]
        )

        let targetSettings = ["Target1": customSettings]

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1",
                            settings: [
                                .init(tool: .linker, name: .unsafeFlags, condition: nil, value: ["key1"]),
                                .init(tool: .linker, name: .unsafeFlags, condition: nil, value: ["key2", "key3"]),
                            ]
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ],
            packageSettings: .test(
                baseSettings: .default,
                targetSettings: targetSettings
            )
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            baseSettings: .settings(
                                base: [
                                    "OTHER_LDFLAGS": ["$(inherited)", "key1", "key2", "key3"],
                                    "CUSTOM_SETTING": "CUSTOM_VALUE",
                                ],
                                configurations: [
                                    .debug(
                                        name: "Custom Debug",
                                        settings: [
                                            "CUSTOM_SETTING_1": .string("CUSTOM_VALUE_1"),
                                            "OTHER_SWIFT_FLAGS": .array([
                                                "-DDEBUG",
                                            ]),
                                        ],
                                        xcconfig: "Sources/Target1/Config.xcconfig"
                                    ),
                                    .release(
                                        name: "Custom Release",
                                        settings: ["CUSTOM_SETTING_3": .string("CUSTOM_VALUE_4")],
                                        xcconfig: "Sources/Target1/Config.xcconfig"
                                    ),
                                ],
                                defaultSettings: .recommended
                            )
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenBaseSettingsContainsDefaultSettingsExcluding_appliesExclusionToTargets() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(name: "Target1"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ],
            packageSettings: .test(
                baseSettings: .init(
                    configurations: [.release: nil, .debug: nil],
                    defaultSettings: .recommended(excluding: ["SWIFT_OPTIMIZATION_LEVEL"])
                )
            )
        )

        let targetSettings = try #require(project?.targets.first?.settings)
        #expect(targetSettings.defaultSettings == .recommended(excluding: ["SWIFT_OPTIMIZATION_LEVEL"]))
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenBaseSettingsContainsDefaultSettingsExcluding_appliesExclusionToProject() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(name: "Target1"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ],
            packageSettings: .test(
                baseSettings: .init(
                    configurations: [.release: nil, .debug: nil],
                    defaultSettings: .recommended(excluding: ["SWIFT_OPTIMIZATION_LEVEL"])
                )
            )
        )

        let projectSettings = try #require(project?.settings)
        #expect(projectSettings.defaultSettings == .recommended(excluding: ["SWIFT_OPTIMIZATION_LEVEL"]))
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenTargetSettingsOverridesBaseSettingsDefaultSettings_usesTargetSettings() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(name: "Target1"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ],
            packageSettings: .test(
                baseSettings: .init(
                    configurations: [.release: nil, .debug: nil],
                    defaultSettings: .recommended(excluding: ["SWIFT_OPTIMIZATION_LEVEL"])
                ),
                targetSettings: [
                    "Target1": .test(defaultSettings: .essential(excluding: ["GCC_OPTIMIZATION_LEVEL"])),
                ]
            )
        )

        let targetSettings = try #require(project?.targets.first?.settings)
        #expect(targetSettings.defaultSettings == .essential(excluding: ["GCC_OPTIMIZATION_LEVEL"]))
    }

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func map_whenConditionalSetting() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1",
                            settings: [
                                .init(
                                    tool: .c,
                                    name: .headerSearchPath,
                                    condition: .init(platformNames: ["tvos"], config: nil),
                                    value: ["value"]
                                ),
                                .init(
                                    tool: .c,
                                    name: .headerSearchPath,
                                    condition: nil,
                                    value: ["otherValue"]
                                ),
                            ]
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            customSettings: [
                                "HEADER_SEARCH_PATHS": [
                                    "$(inherited)",
                                    "$(SRCROOT)/Sources/Target1/otherValue",
                                ],
                                "HEADER_SEARCH_PATHS[sdk=appletvos*]": [
                                    "$(inherited)",
                                    "$(SRCROOT)/Sources/Target1/value",
                                ],
                                "HEADER_SEARCH_PATHS[sdk=appletvsimulator*]": [
                                    "$(inherited)",
                                    "$(SRCROOT)/Sources/Target1/value",
                                ],
                                "OTHER_SWIFT_FLAGS": [
                                    "$(inherited)",
                                ],
                            ]
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenSettingsContainsLinkedFramework_mapsToSDKDependency() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1",
                            settings: [
                                .init(tool: .linker, name: .linkedFramework, condition: nil, value: ["Framework"]),
                            ]
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            dependencies: [.sdk(name: "Framework", type: .framework, status: .required)]
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenSettingsContainsLinkedLibrary_mapsToSDKDependency() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1",
                            settings: [
                                .init(tool: .linker, name: .linkedLibrary, condition: nil, value: ["Library"]),
                            ]
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            dependencies: [.sdk(name: "Library", type: .library, status: .required)]
                        ),
                    ]
                )
        )
    }

    /// SwiftPM links the C++ standard library into every client of a module with C++ sources, so a Swift-only app that links
    /// such a static package target needs it too.
    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenTargetHasCxxSources_linksCxxStandardLibrary() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources"))
        for file in [
            "Cxx/src/nested/Impl.cpp", "Cxx/Header.h",
            "ObjCxx/Bridge.mm",
            "C/Impl.c", "C/windows/Impl.cpp",
            "Selected/Impl.c", "Selected/unused/Impl.cc",
            "Linked/Impl.cpp",
        ] {
            let path = sourcesPath.appending(try RelativePath(validating: file))
            try await fileSystem.makeDirectory(at: path.parentDirectory)
            try await fileSystem.writeText("", at: path)
        }

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(
                            name: "Product1",
                            type: .library(.automatic),
                            targets: ["Cxx", "ObjCxx", "C", "Selected", "Linked"]
                        ),
                    ],
                    targets: [
                        .test(name: "Cxx"),
                        .test(name: "ObjCxx"),
                        .test(name: "C", exclude: ["windows"]),
                        .test(name: "Selected", sources: ["Impl.c"]),
                        .test(name: "Linked", settings: [
                            .init(tool: .linker, name: .linkedLibrary, condition: nil, value: ["c++"]),
                        ]),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        let dependencies = Dictionary(uniqueKeysWithValues: try #require(project).targets.map { ($0.name, $0.dependencies) })
        let cxxStandardLibrary = ProjectDescription.TargetDependency.sdk(name: "c++", type: .library, status: .required)
        #expect(dependencies["Cxx"] == [cxxStandardLibrary])
        #expect(dependencies["ObjCxx"] == [cxxStandardLibrary])
        #expect(dependencies["C"] == [])
        #expect(dependencies["Selected"] == [])
        #expect(dependencies["Linked"] == [cxxStandardLibrary])
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenTargetDependency_mapsToTargetDependency() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        let dependenciesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Dependency1"))
        try await fileSystem.makeDirectory(at: sourcesPath)
        try await fileSystem.makeDirectory(at: dependenciesPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1",
                            dependencies: [.target(name: "Dependency1", condition: nil)]
                        ),
                        .test(name: "Dependency1"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test("Target1", basePath: basePath, dependencies: [.target(name: "Dependency1")]),
                        .test("Dependency1", basePath: basePath),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenBinaryTargetDependency_mapsToXcframework() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        let dependenciesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Dependency1"))
        try await fileSystem.makeDirectory(at: sourcesPath)
        try await fileSystem.makeDirectory(at: dependenciesPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1",
                            dependencies: [.target(name: "Dependency1", condition: nil)]
                        ),
                        .test(name: "Dependency1", type: .binary),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            dependencies: [
                                .xcframework(path: .path(
                                    basePath.appending(try RelativePath(validating: "artifacts/Package/Dependency1.xcframework"))
                                        .pathString
                                )),
                            ]
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenBinaryTargetStaticLibraryArtifactBundleDependency_mapsToGeneratedXcframework() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        let dependenciesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Dependency1"))
        let artifactBundlePath = basePath.appending(
            try RelativePath(validating: "artifacts/Package/Dependency1/Dependency1.artifactbundle")
        )
        try await fileSystem.makeDirectory(at: sourcesPath)
        try await fileSystem.makeDirectory(at: dependenciesPath)
        try await makeStaticLibraryArtifactBundle(at: artifactBundlePath, targetName: "Dependency1")
        let generatedXCFrameworkPath = try await generatedStaticLibraryArtifactBundleXCFrameworkPath(
            basePath: basePath,
            packageName: "Package",
            targetName: "Dependency1",
            artifactBundlePath: artifactBundlePath
        )

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageType: .external(artifactPaths: ["Dependency1": artifactBundlePath]),
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1",
                            dependencies: [.target(name: "Dependency1", condition: nil)]
                        ),
                        .test(name: "Dependency1", type: .binary),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            dependencies: [
                                .xcframework(path: .path(generatedXCFrameworkPath.pathString)),
                            ]
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenTargetByNameDependency_mapsToTargetDependency() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        let dependenciesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Dependency1"))
        try await fileSystem.makeDirectory(at: sourcesPath)
        try await fileSystem.makeDirectory(at: dependenciesPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1",
                            dependencies: [.byName(name: "Dependency1", condition: nil)]
                        ),
                        .test(name: "Dependency1"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test("Target1", basePath: basePath, dependencies: [.target(name: "Dependency1")]),
                        .test("Dependency1", basePath: basePath),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenBinaryTargetURLByNameDependency_mapsToXcFramework() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1",
                            dependencies: [
                                .byName(name: "Dependency1", condition: nil),
                            ]
                        ),
                        .test(name: "Dependency1", type: .binary, url: "someURL"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            dependencies: [
                                .xcframework(path: .path(
                                    basePath.appending(try RelativePath(validating: "artifacts/Package/Dependency1.xcframework"))
                                        .pathString
                                )),
                            ]
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenBinaryTargetXcframeworkPathByNameDependency_mapsToXcFramework() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1",
                            dependencies: [
                                .byName(name: "Dependency1", condition: nil),
                            ]
                        ),
                        .test(name: "Dependency1", type: .binary, path: "Package/Sources/Target1/Dependency1.xcframework"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            dependencies: [.xcframework(path: .path(
                                basePath
                                    .appending(try RelativePath(validating: "Package/Sources/Target1/Dependency1.xcframework"))
                                    .pathString
                            ))]
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenBinaryTargetZipPathByNameDependency_mapsToXcFramework() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1",
                            dependencies: [
                                .byName(name: "Dependency1", condition: nil),
                            ]
                        ),
                        .test(name: "Dependency1", type: .binary, path: "Package/Sources/Target1/Dependency1.xcframework.zip"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            dependencies: [.xcframework(path: .path(
                                basePath
                                    .appending(try RelativePath(validating: "artifacts/Package/Dependency1.xcframework"))
                                    .pathString
                            ))]
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenExternalProductDependency_mapsToProjectDependencies() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/Target1")))
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package2/Sources/Target2")))
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package2/Sources/Target3")))
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package2/Sources/Target4")))
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/Dependency1")))

        let package1 = PackageInfo.test(
            name: "Package",
            products: [
                .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
            ],
            targets: [
                .test(
                    name: "Target1",
                    dependencies: [.product(name: "Product2", package: "Package2", moduleAliases: nil, condition: nil)]
                ),
                .test(name: "Dependency1"),
            ],
            platforms: [.ios],
            cLanguageStandard: nil,
            cxxLanguageStandard: nil,
            swiftLanguageVersions: nil
        )
        let package2 = PackageInfo.test(
            name: "Package2",
            products: [
                .init(name: "Product2", type: .library(.automatic), targets: ["Target2", "Target3"]),
                .init(name: "Product3", type: .library(.automatic), targets: ["Target4"]),
            ],
            targets: [
                .test(name: "Target2"),
                .test(name: "Target3"),
                .test(name: "Target4"),
            ],
            platforms: [.ios],
            cLanguageStandard: nil,
            cxxLanguageStandard: nil,
            swiftLanguageVersions: nil
        )
        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: ["Package": package1, "Package2": package2]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            dependencies: [
                                .external(name: "Product2", condition: nil),
                            ]
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenProductDependencyHasSameNameAsLocalTarget_mapsToExternalDependency() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/Foo")))

        let package1 = PackageInfo.test(
            name: "Package",
            products: [
                .init(name: "Product1", type: .library(.automatic), targets: ["Foo"]),
            ],
            targets: [
                .test(
                    name: "Foo",
                    dependencies: [.product(name: "Foo", package: "ExternalFoo", moduleAliases: nil, condition: nil)]
                ),
            ],
            platforms: [.ios],
            cLanguageStandard: nil,
            cxxLanguageStandard: nil,
            swiftLanguageVersions: nil
        )
        let package2 = PackageInfo.test(
            name: "ExternalFoo",
            products: [
                .init(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
            ],
            targets: [
                .test(name: "Foo"),
            ],
            platforms: [.ios],
            cLanguageStandard: nil,
            cxxLanguageStandard: nil,
            swiftLanguageVersions: nil
        )
        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: ["Package": package1, "ExternalFoo": package2]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Foo",
                            basePath: basePath,
                            dependencies: [
                                .external(name: "Foo", condition: nil),
                            ]
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenProductDependencyHasSameNameAsLocalTargetWithModuleAlias_mapsToTargetDependency() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/Foo")))

        let package1 = PackageInfo.test(
            name: "Package",
            products: [
                .init(name: "Product1", type: .library(.automatic), targets: ["Foo"]),
            ],
            targets: [
                .test(
                    name: "Foo",
                    dependencies: [
                        .product(
                            name: "Foo",
                            package: "ExternalFoo",
                            moduleAliases: ["Foo": "ExternalFooTarget"],
                            condition: nil
                        ),
                    ]
                ),
            ],
            platforms: [.ios],
            cLanguageStandard: nil,
            cxxLanguageStandard: nil,
            swiftLanguageVersions: nil
        )
        let package2 = PackageInfo.test(
            name: "ExternalFoo",
            products: [
                .init(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
            ],
            targets: [
                .test(name: "Foo"),
            ],
            platforms: [.ios],
            cLanguageStandard: nil,
            cxxLanguageStandard: nil,
            swiftLanguageVersions: nil
        )
        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: ["Package": package1, "ExternalFoo": package2]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Foo",
                            basePath: basePath,
                            dependencies: [
                                .target(name: "ExternalFooTarget", condition: nil),
                            ],
                            customSettings: ["OTHER_SWIFT_FLAGS": ["$(inherited)", "-module-alias", "Foo=ExternalFooTarget"]]
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenProductDependencyNamesItsPackage_mapsToTheProductOfThatPackage() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(
            at: basePath.appending(try RelativePath(validating: "Package/Sources/PackageIssueReporting"))
        )

        let package = PackageInfo.test(
            name: "Package",
            products: [
                .init(name: "IssueReporting", type: .library(.automatic), targets: ["PackageIssueReporting"]),
            ],
            targets: [
                .test(
                    name: "PackageIssueReporting",
                    dependencies: [
                        .product(
                            name: "IssueReporting",
                            package: "swift-issue-reporting",
                            moduleAliases: nil,
                            condition: .init(platformNames: ["ios"], config: nil)
                        ),
                    ]
                ),
            ],
            platforms: [.ios],
            cLanguageStandard: nil,
            cxxLanguageStandard: nil,
            swiftLanguageVersions: nil
        )
        let issueReportingPackage = PackageInfo.test(
            name: "swift-issue-reporting",
            products: [
                .init(name: "IssueReporting", type: .library(.automatic), targets: ["IssueReporting"]),
            ],
            targets: [
                .test(name: "IssueReporting"),
            ],
            platforms: [.ios],
            cLanguageStandard: nil,
            cxxLanguageStandard: nil,
            swiftLanguageVersions: nil
        )
        let packageInfos = ["Package": package, "swift-issue-reporting": issueReportingPackage]
        let issueReportingPackageFolder = basePath.appending(component: "swift-issue-reporting")
        let externalDependencies = try await subject.resolveExternalDependencies(
            path: basePath,
            packageInfos: packageInfos,
            packageToFolder: [
                "Package": basePath.appending(component: "Package"),
                "swift-issue-reporting": issueReportingPackageFolder,
            ],
            packageToTargetsToArtifactPaths: [:],
            packageModuleAliases: [:],
            packageSettings: .test()
        )

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: packageInfos,
            packageProducts: externalDependencies.packageProducts
        )

        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "PackageIssueReporting",
                            basePath: basePath,
                            dependencies: [
                                .project(
                                    target: "IssueReporting",
                                    path: .path(issueReportingPackageFolder.pathString),
                                    condition: .when([.ios])
                                ),
                            ]
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenProductDependencyNamesARegistryPackageOverriddenLocally_mapsToTheProductOfTheLocalPackage() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(
            at: basePath.appending(try RelativePath(validating: "acme.client/Sources/Client"))
        )

        let client = PackageInfo.test(
            name: "Client",
            products: [
                .init(name: "Client", type: .library(.automatic), targets: ["Client"]),
            ],
            targets: [
                .test(
                    name: "Client",
                    dependencies: [
                        .product(name: "Core", package: "acme.Kit", moduleAliases: nil, condition: nil),
                    ]
                ),
            ],
            platforms: [.ios],
            cLanguageStandard: nil,
            cxxLanguageStandard: nil,
            swiftLanguageVersions: nil
        )
        // The local `../ios-Kit` checkout replaced `acme.Kit`, and an unrelated package vends a product with the same name.
        let localKit = PackageInfo.test(
            name: "Kit",
            products: [.init(name: "Core", type: .library(.automatic), targets: ["KitCore"])],
            targets: [.test(name: "KitCore")],
            platforms: [.ios]
        )
        let other = PackageInfo.test(
            name: "Other",
            products: [.init(name: "Core", type: .library(.automatic), targets: ["OtherCore"])],
            targets: [.test(name: "OtherCore")],
            platforms: [.ios]
        )
        let packageInfos = ["acme.client": client, "ios-kit": localKit, "acme.other": other]
        let localKitFolder = basePath.appending(component: "ios-Kit")
        let externalDependencies = try await subject.resolveExternalDependencies(
            path: basePath,
            packageInfos: packageInfos,
            packageToFolder: [
                "acme.client": basePath.appending(component: "acme.client"),
                "ios-kit": localKitFolder,
                "acme.other": basePath.appending(component: "Other"),
            ],
            packageToTargetsToArtifactPaths: [:],
            packageModuleAliases: [:],
            packageSettings: .test()
        )

        let project = try await subject.map(
            package: "acme.client",
            basePath: basePath,
            packageInfos: packageInfos,
            packageProducts: externalDependencies.packageProducts
        )

        #expect(
            project?.targets.first?.dependencies == [
                .project(target: "KitCore", path: .path(localKitFolder.pathString)),
            ]
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func resolveDependencies_keysPackageProductsByIdentityManifestNameAndRegistryName() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let issueReportingFolder = basePath.appending(component: "swift-issue-reporting")
        let overlayFolder = basePath.appending(component: "xctest-dynamic-overlay")

        let resolvedDependencies = try await subject.resolveExternalDependencies(
            path: basePath,
            packageInfos: [
                "pointfreeco.swift-issue-reporting": .test(
                    name: "IssueReportingPackage",
                    products: [
                        .init(name: "IssueReporting", type: .library(.automatic), targets: ["IssueReporting"]),
                    ],
                    targets: [.test(name: "IssueReporting")],
                    platforms: [.ios]
                ),
                "pointfreeco.xctest-dynamic-overlay": .test(
                    name: "xctest-dynamic-overlay",
                    products: [
                        .init(name: "IssueReporting", type: .library(.automatic), targets: ["_IssueReporting"]),
                    ],
                    targets: [.test(name: "_IssueReporting")],
                    platforms: [.ios]
                ),
            ],
            packageToFolder: [
                "pointfreeco.swift-issue-reporting": issueReportingFolder,
                "pointfreeco.xctest-dynamic-overlay": overlayFolder,
            ],
            packageToTargetsToArtifactPaths: [:],
            packageModuleAliases: [:],
            packageSettings: .test()
        )

        let issueReportingProducts: [String: [ProjectDescription.TargetDependency]] = [
            "IssueReporting": [.project(target: "IssueReporting", path: .path(issueReportingFolder.pathString))],
        ]
        let overlayProducts: [String: [ProjectDescription.TargetDependency]] = [
            "IssueReporting": [.project(target: "_IssueReporting", path: .path(overlayFolder.pathString))],
        ]
        #expect(
            resolvedDependencies == ResolvedExternalDependencies(
                products: overlayProducts,
                packageProducts: [
                    "pointfreeco.swift-issue-reporting": issueReportingProducts,
                    "issuereportingpackage": issueReportingProducts,
                    "swift-issue-reporting": issueReportingProducts,
                    "pointfreeco.xctest-dynamic-overlay": overlayProducts,
                    "xctest-dynamic-overlay": overlayProducts,
                ]
            )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func resolveDependencies_whenPackagesShareAManifestName_doesNotKeyPackageProductsByIt() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let chartsFolder = basePath.appending(component: "charts")
        let chartsForkFolder = basePath.appending(component: "charts-fork")

        let resolvedDependencies = try await subject.resolveExternalDependencies(
            path: basePath,
            packageInfos: [
                "charts": .test(
                    name: "DGCharts",
                    products: [.init(name: "DGCharts", type: .library(.automatic), targets: ["DGCharts"])],
                    targets: [.test(name: "DGCharts")],
                    platforms: [.ios]
                ),
                "charts-fork": .test(
                    name: "DGCharts",
                    products: [.init(name: "DGChartsFork", type: .library(.automatic), targets: ["DGChartsFork"])],
                    targets: [.test(name: "DGChartsFork")],
                    platforms: [.ios]
                ),
            ],
            packageToFolder: ["charts": chartsFolder, "charts-fork": chartsForkFolder],
            packageToTargetsToArtifactPaths: [:],
            packageModuleAliases: [:],
            packageSettings: .test()
        )

        #expect(Set(resolvedDependencies.packageProducts.keys) == ["charts", "charts-fork"])
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenProductDependencyReferencesSamePackage_mapsToTargetDependency() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/Bar")))
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/Foo")))

        let package1 = PackageInfo.test(
            name: "Package",
            products: [
                .init(name: "Product1", type: .library(.automatic), targets: ["Bar"]),
                .init(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
            ],
            targets: [
                .test(
                    name: "Bar",
                    dependencies: [.product(name: "Foo", package: "Package", moduleAliases: nil, condition: nil)]
                ),
                .test(name: "Foo"),
            ],
            platforms: [.ios],
            cLanguageStandard: nil,
            cxxLanguageStandard: nil,
            swiftLanguageVersions: nil
        )
        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: ["Package": package1]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Bar",
                            basePath: basePath,
                            dependencies: [
                                .target(name: "Foo", condition: nil),
                            ]
                        ),
                        .test("Foo", basePath: basePath),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenExternalByNameProductDependency_mapsToProjectDependencies() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/Target1")))
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package2/Sources/Target2")))
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package2/Sources/Target3")))
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package2/Sources/Target4")))
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/Dependency1")))

        let package1 = PackageInfo.test(
            name: "Package",
            products: [
                .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
            ],
            targets: [
                .test(
                    name: "Target1",
                    dependencies: [.byName(name: "Product2", condition: nil)]
                ),
                .test(name: "Dependency1"),
            ],
            platforms: [.ios],
            cLanguageStandard: nil,
            cxxLanguageStandard: nil,
            swiftLanguageVersions: nil
        )
        let package2 = PackageInfo.test(
            name: "Package2",
            products: [
                .init(name: "Product2", type: .library(.automatic), targets: ["Target2", "Target3"]),
                .init(name: "Product3", type: .library(.automatic), targets: ["Target4"]),
            ],
            targets: [
                .test(name: "Target2"),
                .test(name: "Target3"),
                .test(name: "Target4"),
            ],
            platforms: [.ios],
            cLanguageStandard: nil,
            cxxLanguageStandard: nil,
            swiftLanguageVersions: nil
        )
        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: ["Package": package1, "Package2": package2]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            dependencies: [
                                .external(name: "Product2", condition: nil),
                            ]
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenCustomCVersion_mapsToGccCLanguageStandardSetting() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(name: "Target1"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: "c99",
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    settings: .settings(base: ["GCC_C_LANGUAGE_STANDARD": "c99", "SWIFT_VERSION": "5"]),
                    targets: [
                        .test("Target1", basePath: basePath),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenCustomCXXVersion_mapsToClangCxxLanguageStandardSetting() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(name: "Target1"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: "gnu++14",
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    settings: .settings(base: ["CLANG_CXX_LANGUAGE_STANDARD": "gnu++14", "SWIFT_VERSION": "5"]),
                    targets: [
                        .test("Target1", basePath: basePath),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenCustomSwiftVersion_mapsToSwiftVersionSetting() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(name: "Target1"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: ["4.0.0"]
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    settings: .settings(base: ["SWIFT_VERSION": "4.0.0"]),
                    targets: [
                        .test("Target1", basePath: basePath),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenMultipleCustomSwiftVersions_mapsLargestToSwiftVersionSetting() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(name: "Target1"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: ["4.0.0", "5.0.0", "4.2.0"]
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    settings: .settings(base: ["SWIFT_VERSION": "5.0.0"]),
                    targets: [
                        .test("Target1", basePath: basePath),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_whenMultipleCustomSwiftVersionsAndConfiguredVersion_mapsLargestToSwiftVersionLowerThanConfigured(
    ) async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(name: "Target1"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: ["5.0.0", "6.0.0", "5.9.0"],
                    toolsVersion: Version(5, 9, 0)
                ),
            ],
            packageSettings: .test(
                baseSettings: .default
            )
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    settings: .settings(base: ["SWIFT_VERSION": "5.9.0"]),
                    targets: [
                        .test("Target1", basePath: basePath),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenDependenciesContainsCustomConfiguration_mapsToProjectWithCustomConfig(
    ) async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(name: "Target1"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ],
            packageSettings: .test(
                baseSettings: Settings(
                    configurations: [.release: nil, .debug: nil, .init(name: "Custom", variant: .release): nil],
                    defaultSettings: .recommended
                )
            )
        )

        #expect(project?.settings?.configurations.first(where: { $0.name == "Custom" }) != nil)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenTargetsWithDefaultHardcodedMapping() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let testTargets = [
            "Nimble",
            "Quick",
            "RxTest",
            "RxTest-Dynamic",
            "SnapshotTesting",
            "IssueReportingTestSupport",
            "TempuraTesting",
            "TSCTestSupport",
            "ViewInspector",
            "XCTVapor",
        ]
        let allTargets = ["RxSwift"] + testTargets
        let targetPaths = try allTargets
            .map { basePath.appending(try RelativePath(validating: "Package/Sources/\($0)")) }
        for path in targetPaths {
            try await fileSystem.makeDirectory(at: path)
        }

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: allTargets),
                    ],
                    targets: allTargets.map { .test(name: $0) },
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ],
            packageSettings: .test(
                baseSettings: .default,
                targetSettings: [
                    "Nimble": .test(base: ["ENABLE_TESTING_SEARCH_PATHS": "NO", "ANOTHER_SETTING": "YES"]),
                    "Quick": .test(base: ["ANOTHER_SETTING": "YES"]),
                ]
            )
        )

        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test("RxSwift", basePath: basePath, product: .framework),
                    ] + testTargets.map {
                        var customSettings: ProjectDescription.SettingsDictionary
                        var customProductName: String?
                        switch $0 {
                        case "Nimble":
                            customSettings = ["ENABLE_TESTING_SEARCH_PATHS": "NO", "ANOTHER_SETTING": "YES"]
                        case "Quick":
                            customSettings = ["ENABLE_TESTING_SEARCH_PATHS": "YES", "ANOTHER_SETTING": "YES"]
                        case "RxTest-Dynamic": // because RxTest does have an "-" we need to account for the custom mapping to
                            // product
                            // names
                            customProductName = "RxTest_Dynamic"
                            customSettings = ["ENABLE_TESTING_SEARCH_PATHS": "YES"]
                        default:
                            customSettings = ["ENABLE_TESTING_SEARCH_PATHS": "YES"]
                        }
                        customSettings["OTHER_SWIFT_FLAGS"] = [
                            "$(inherited)",
                        ]

                        return .test(
                            $0,
                            basePath: basePath,
                            customProductName: customProductName,
                            customSettings: customSettings
                        )
                    }
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenTargetDependenciesOnTargetHaveConditions() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/Target1")))
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/Dependency1")))
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/Dependency2")))

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1",
                            dependencies: [
                                .target(name: "Dependency1", condition: .init(platformNames: ["ios"], config: nil)),
                                .target(name: "Dependency2", condition: .init(platformNames: ["tvos"], config: nil)),
                                .target(name: "External", condition: .init(platformNames: ["ios"], config: nil)),
                            ]
                        ),
                        .test(name: "Dependency1"),
                        .test(name: "Dependency2"),
                        .test(name: "External", type: .binary),
                    ],
                    platforms: [.ios, .tvos],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )

        let expected: ProjectDescription.Project = .testWithDefaultConfigs(
            name: "Package",
            targets: [
                .test(
                    "Target1",
                    basePath: basePath,
                    customProductName: "Target1",
                    customBundleID: "Target1",
                    customSources: .custom(.sourceFilesList(globs: [
                        basePath.appending(try RelativePath(validating: "Package/Sources/Target1/**")).pathString,
                    ])),
                    dependencies: [
                        .target(name: "Dependency1", condition: .when([.ios])),
                        .target(name: "Dependency2", condition: .when([.tvos])),
                        .xcframework(
                            path: .relativeToManifest(
                                basePath
                                    .appending(try RelativePath(validating: "artifacts/Package/External.xcframework")).pathString
                            ),
                            status: .required,
                            condition: .when([.ios])
                        ),
                    ]
                ),
                .test(
                    "Dependency1",
                    basePath: basePath,
                    customProductName: "Dependency1",
                    customBundleID: "Dependency1",
                    customSources: .custom(.sourceFilesList(globs: [
                        basePath.appending(try RelativePath(validating: "Package/Sources/Dependency1/**")).pathString,
                    ]))
                ),
                .test(
                    "Dependency2",
                    basePath: basePath,
                    customProductName: "Dependency2",
                    customBundleID: "Dependency2",
                    customSources: .custom(.sourceFilesList(globs: [
                        basePath.appending(try RelativePath(validating: "Package/Sources/Dependency2/**")).pathString,
                    ]))
                ),
            ]
        )

        #expect(project?.name == expected.name)

        let projectTargets = try #require(project?.targets.sorted(by: \.name))
        let expectedTargets = expected.targets.sorted(by: \.name)

        #expect(projectTargets == expectedTargets)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenTargetDependenciesOnProductHaveConditions() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)

        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/Target1")))
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package2/Sources/Target2")))
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package2/Sources/Target3")))

        let package1 = PackageInfo.test(
            name: "Package",
            products: [
                .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
            ],
            targets: [
                .test(
                    name: "Target1",
                    dependencies: [
                        .product(
                            name: "Product2",
                            package: "Package2",
                            moduleAliases: nil,
                            condition: .init(platformNames: ["ios"], config: nil)
                        ),
                    ]
                ),
            ],
            platforms: [.ios, .tvos],
            cLanguageStandard: nil,
            cxxLanguageStandard: nil,
            swiftLanguageVersions: nil
        )
        let package2 = PackageInfo.test(
            name: "Package2",
            products: [
                .init(name: "Product2", type: .library(.automatic), targets: ["Target2", "Target3"]),
            ],
            targets: [
                .test(name: "Target2"),
                .test(name: "Target3"),
            ],
            platforms: [.ios, .tvos],
            cLanguageStandard: nil,
            cxxLanguageStandard: nil,
            swiftLanguageVersions: nil
        )
        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: ["Package": package1, "Package2": package2]
        )

        let expected: ProjectDescription.Project = .testWithDefaultConfigs(
            name: "Package",
            targets: [
                .test(
                    "Target1",
                    basePath: basePath,
                    customProductName: "Target1",
                    customBundleID: "Target1",
                    customSources: .custom(.sourceFilesList(globs: [
                        basePath.appending(try RelativePath(validating: "Package/Sources/Target1/**")).pathString,
                    ])),
                    dependencies: [
                        .external(name: "Product2", condition: .when([.ios])),
                    ]
                ),
            ]
        )

        #expect(project?.name == expected.name)

        let projectTargets = try #require(project?.targets.sorted(by: \.name))
        let expectedTargets = expected.targets.sorted(by: \.name)

        #expect(
            projectTargets ==
                expectedTargets
        )
    }

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func map_whenTargetNameContainsSpaces() async throws {
        let packageName = "Package With Space"
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "\(packageName)/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)

        let project = try await subject.map(
            package: packageName,
            basePath: basePath,
            packageInfos: [
                packageName: .test(
                    name: packageName,
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(name: "Target1"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: packageName,
                    targets: [
                        .test(
                            "Target1",
                            packageName: packageName,
                            basePath: basePath
                        ),
                    ]
                )
        )
    }

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func map_whenSwiftPackageHasTestTarget() async throws {
        // Given
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(components: ["Package", "Sources", "Target"])
        try await fileSystem.makeDirectory(at: sourcesPath)
        let testsPath = basePath.appending(components: ["Package", "Tests", "TargetTests"])
        try await fileSystem.makeDirectory(at: testsPath)

        // When
        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageType: .local,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product", type: .library(.automatic), targets: ["Target"]),
                    ],
                    targets: [
                        .test(name: "Target"),
                        .test(
                            name: "TargetTests",
                            type: .test,
                            dependencies: [.target(name: "Target", condition: nil)]
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )

        // Then
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    options: .options(
                        automaticSchemesOptions: .enabled(),
                        disableSynthesizedResourceAccessors: true
                    ),
                    settings: .settings(base: ["SWIFT_VERSION": "5"]),
                    targets: [
                        .test("Target", basePath: basePath),
                        .test(
                            "TargetTests",
                            basePath: basePath,
                            product: .unitTests,
                            customSources: .custom(.sourceFilesList(globs: [
                                "\(testsPath.pathString)/**",
                            ])),
                            dependencies: [.target(name: "Target")]
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenExternalLocalSwiftPackageHasTestTarget_ignoresTestTarget() async throws {
        // Given
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(components: ["Package", "Sources", "Target"])
        try await fileSystem.makeDirectory(at: sourcesPath)
        let testsPath = basePath.appending(components: ["Package", "Tests", "TargetTests"])
        try await fileSystem.makeDirectory(at: testsPath)

        // When
        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageType: .external(origin: .local, artifactPaths: [:]),
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product", type: .library(.automatic), targets: ["Target"]),
                    ],
                    targets: [
                        .test(name: "Target"),
                        .test(
                            name: "TargetTests",
                            type: .test,
                            dependencies: [.target(name: "Target", condition: nil)]
                        ),
                    ],
                    platforms: [.ios]
                ),
            ]
        )

        // Then
        #expect(project != nil)
        #expect(Set(project?.targets.map(\.name) ?? []) == Set(["Target"]))
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenExternalLocalSwiftPackageHasTestTarget_andTestsAreEnabled_includesTestTarget() async throws {
        // Given
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(components: ["Package", "Sources", "Target"])
        try await fileSystem.makeDirectory(at: sourcesPath)
        let testsPath = basePath.appending(components: ["Package", "Tests", "TargetTests"])
        try await fileSystem.makeDirectory(at: testsPath)

        // When
        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageType: .external(origin: .local, artifactPaths: [:]),
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product", type: .library(.automatic), targets: ["Target"]),
                    ],
                    targets: [
                        .test(name: "Target"),
                        .test(
                            name: "TargetTests",
                            type: .test,
                            dependencies: [.target(name: "Target", condition: nil)]
                        ),
                    ],
                    platforms: [.ios]
                ),
            ],
            packageSettings: .test(
                baseSettings: .default,
                includeLocalPackageTestTargets: true
            )
        )

        // Then
        #expect(project != nil)
        #expect(Set(project?.targets.map(\.name) ?? []) == Set(["Target", "TargetTests"]))
        let testTarget = project?.targets.first(where: { $0.name == "TargetTests" })
        #expect(testTarget?.product == .unitTests)
        #expect(testTarget?.metadata.tags.contains(TargetTags.localSwiftPackageTest) == true)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider,
        arguments: [false, true]
    ) func map_whenEnabledExternalLocalPackageTestDependsOnExternalProduct_includesDependency(
        usesByName: Bool
    ) async throws {
        let dependency: PackageInfo.Target.Dependency = usesByName
            ? .byName(name: "TestSupport", condition: nil)
            : .product(name: "TestSupport", package: "TestSupportPackage", moduleAliases: nil, condition: nil)
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(at: basePath.appending(components: "Package", "Sources", "Target"))
        try await fileSystem.makeDirectory(at: basePath.appending(components: "Package", "Tests", "TargetTests"))

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageType: .external(origin: .local, artifactPaths: [:]),
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [.init(name: "Product", type: .library(.automatic), targets: ["Target"])],
                    targets: [
                        .test(name: "Target"),
                        .test(
                            name: "TargetTests",
                            type: .test,
                            dependencies: [.target(name: "Target", condition: nil), dependency]
                        ),
                    ],
                    platforms: [.ios]
                ),
            ],
            packageSettings: .test(includeLocalPackageTestTargets: true)
        )

        let testTarget = try #require(project?.targets.first(where: { $0.name == "TargetTests" }))
        #expect(testTarget.product == .unitTests)
        #expect(testTarget.metadata.tags.contains(TargetTags.localSwiftPackageTest))
        #expect(testTarget.dependencies == [.target(name: "Target"), .external(name: "TestSupport")])
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenEnabledExternalLocalPackageTestDependsOnExecutableTarget_throwsConcreteError() async throws {
        // Given
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(components: ["Package", "Sources", "MyTool"])
        try await fileSystem.makeDirectory(at: sourcesPath)
        let testsPath = basePath.appending(components: ["Package", "Tests", "MyToolTests"])
        try await fileSystem.makeDirectory(at: testsPath)

        // When / Then
        await #expect(
            throws: PackageInfoMapperError.unsupportedExecutableTargetInLocalPackageTest(
                package: "Package",
                target: "MyToolTests",
                executable: "MyTool"
            )
        ) {
            _ = try await subject.map(
                package: "Package",
                basePath: basePath,
                packageType: .external(origin: .local, artifactPaths: [:]),
                packageInfos: [
                    "Package": .test(
                        name: "Package",
                        products: [
                            .init(name: "MyTool", type: .executable, targets: ["MyTool"]),
                        ],
                        targets: [
                            .test(name: "MyTool", type: .executable),
                            .test(
                                name: "MyToolTests",
                                type: .test,
                                dependencies: [.target(name: "MyTool", condition: nil)]
                            ),
                        ],
                        platforms: [.macos]
                    ),
                ],
                packageSettings: .test(includeLocalPackageTestTargets: true)
            )
        }
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenExternalRemoteSwiftPackageHasTestTarget_andTestsAreEnabled_ignoresTestTarget() async throws {
        // Given
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(components: ["Package", "Sources", "Target"])
        try await fileSystem.makeDirectory(at: sourcesPath)
        let testsPath = basePath.appending(components: ["Package", "Tests", "TargetTests"])
        try await fileSystem.makeDirectory(at: testsPath)

        // When
        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageType: .external(origin: .remote, artifactPaths: [:]),
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product", type: .library(.automatic), targets: ["Target"]),
                    ],
                    targets: [
                        .test(name: "Target"),
                        .test(
                            name: "TargetTests",
                            type: .test,
                            dependencies: [.target(name: "Target", condition: nil)]
                        ),
                    ],
                    platforms: [.ios]
                ),
            ],
            packageSettings: .test(includeLocalPackageTestTargets: true)
        )

        // Then
        #expect(project != nil)
        #expect(Set(project?.targets.map(\.name) ?? []) == Set(["Target"]))
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenSwiftPackageHasTestTargetWithExplicitProductDestinations() async throws {
        // Given
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(components: ["Package", "Sources", "Target"])
        try await fileSystem.makeDirectory(at: sourcesPath)
        let testsPath = basePath.appending(components: ["Package", "Tests", "TargetTests"])
        try await fileSystem.makeDirectory(at: testsPath)

        // When
        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageType: .local,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product", type: .library(.automatic), targets: ["Target"]),
                    ],
                    targets: [
                        .test(name: "Target"),
                        .test(
                            name: "TargetTests",
                            type: .test,
                            dependencies: [.target(name: "Target", condition: nil)]
                        ),
                    ],
                    platforms: [.ios, .macos],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ],
            packageSettings: .test(
                productDestinations: ["Product": [.iPhone, .iPad]]
            )
        )

        // Then
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    options: .options(
                        automaticSchemesOptions: .enabled(),
                        disableSynthesizedResourceAccessors: true
                    ),
                    settings: .settings(base: ["SWIFT_VERSION": "5"]),
                    targets: [
                        .test(
                            "Target",
                            basePath: basePath,
                            destinations: [.iPhone, .iPad],
                            deploymentTargets: .iOS("12.0")
                        ),
                        .test(
                            "TargetTests",
                            basePath: basePath,
                            destinations: [.iPhone, .iPad],
                            product: .unitTests,
                            deploymentTargets: .iOS("12.0"),
                            customSources: .custom(.sourceFilesList(globs: [
                                "\(testsPath.pathString)/**",
                            ])),
                            dependencies: [.target(name: "Target")]
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenSwiftPackageHasMultiDependencyTestTargetsWithExplicitProductDestinations(
    ) async throws {
        // Given
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(at: basePath.appending(components: ["Package", "Sources", "Target"]))
        try await fileSystem.makeDirectory(at: basePath.appending(components: ["Package", "Sources", "MacTarget"]))
        try await fileSystem.makeDirectory(at: basePath.appending(components: ["Package", "Sources", "CommonTarget"]))
        let productTestsPath = basePath.appending(components: ["Package", "Tests", "ProductTests"])
        try await fileSystem.makeDirectory(at: productTestsPath)
        let macProductTestsPath = basePath.appending(components: ["Package", "Tests", "MacProductTests"])
        try await fileSystem.makeDirectory(at: macProductTestsPath)

        // When
        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageType: .local,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(
                            name: "Product",
                            type: .library(.automatic),
                            targets: ["Target", "CommonTarget"]
                        ),
                        .init(
                            name: "MacProduct",
                            type: .library(.automatic),
                            targets: ["MacTarget", "CommonTarget"]
                        ),
                    ],
                    targets: [
                        .test(name: "Target"),
                        .test(name: "MacTarget"),
                        .test(name: "CommonTarget"),
                        .test(
                            name: "ProductTests",
                            type: .test,
                            dependencies: [
                                .target(name: "Target", condition: nil),
                                .target(name: "CommonTarget", condition: nil),
                            ]
                        ),
                        .test(
                            name: "MacProductTests",
                            type: .test,
                            dependencies: [
                                .target(name: "MacTarget", condition: nil),
                                .target(name: "CommonTarget", condition: nil),
                            ]
                        ),
                    ],
                    platforms: [.ios, .macos],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ],
            packageSettings: .test(
                productDestinations: ["MacProduct": [.mac]]
            )
        )

        // Then
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    options: .options(
                        automaticSchemesOptions: .enabled(),
                        disableSynthesizedResourceAccessors: true
                    ),
                    settings: .settings(base: ["SWIFT_VERSION": "5"]),
                    targets: [
                        .test("Target", basePath: basePath),
                        .test(
                            "MacTarget",
                            basePath: basePath,
                            destinations: [.mac],
                            deploymentTargets: .macOS("10.13")
                        ),
                        .test("CommonTarget", basePath: basePath),
                        .test(
                            "ProductTests",
                            basePath: basePath,
                            product: .unitTests,
                            customSources: .custom(.sourceFilesList(globs: [
                                "\(productTestsPath.pathString)/**",
                            ])),
                            dependencies: [
                                .target(name: "Target"),
                                .target(name: "CommonTarget"),
                            ]
                        ),
                        .test(
                            "MacProductTests",
                            basePath: basePath,
                            destinations: [.mac],
                            product: .unitTests,
                            deploymentTargets: .macOS("10.13"),
                            customSources: .custom(.sourceFilesList(globs: [
                                "\(macProductTestsPath.pathString)/**",
                            ])),
                            dependencies: [
                                .target(name: "MacTarget"),
                                .target(name: "CommonTarget"),
                            ]
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenSwiftPackageHasTestTargetWithExternalDependency() async throws {
        // Given
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(components: ["Package", "Sources", "Target"])
        try await fileSystem.makeDirectory(at: sourcesPath)
        let testsPath = basePath.appending(components: ["Package", "Tests", "TargetTests"])
        try await fileSystem.makeDirectory(at: testsPath)

        // When
        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageType: .local,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Product", type: .library(.automatic), targets: ["Target"]),
                    ],
                    targets: [
                        .test(name: "Target"),
                        .test(
                            name: "TargetTests",
                            type: .test,
                            dependencies: [
                                .target(name: "Target", condition: nil),
                                .product(name: "External", package: "External", moduleAliases: nil, condition: nil),
                            ]
                        ),
                    ]
                ),
            ]
        )

        // Then
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    options: .options(
                        automaticSchemesOptions: .enabled(),
                        disableSynthesizedResourceAccessors: true
                    ),
                    settings: .settings(base: ["SWIFT_VERSION": "5"]),
                    targets: [
                        .test("Target", basePath: basePath),
                        .test(
                            "TargetTests",
                            basePath: basePath,
                            product: .unitTests,
                            customSources: .custom(.sourceFilesList(globs: [
                                "\(testsPath.pathString)/**",
                            ])),
                            dependencies: [
                                .target(name: "Target"),
                                .external(name: "External", condition: nil),
                            ]
                        ),
                    ]
                )
        )
    }

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func map_whenHasModuleAliases() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/Product")))
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package2/Sources/Product")))
        let packageInfos: [String: PackageInfo] = [
            "Package": .test(
                name: "Package",
                products: [
                    .init(name: "Product", type: .library(.automatic), targets: ["Product"]),
                ],
                targets: [
                    .test(
                        name: "Product",
                        dependencies: [
                            .product(
                                name: "Product",
                                package: "Package2",
                                moduleAliases: ["Product": "Package2Product"],
                                condition: nil
                            ),
                        ]
                    ),
                ],
                platforms: [.ios],
                cLanguageStandard: nil,
                cxxLanguageStandard: nil,
                swiftLanguageVersions: nil
            ),
            "Package2": .test(
                name: "Package2",
                products: [
                    .init(name: "Product", type: .library(.automatic), targets: ["Product"]),
                ],
                targets: [
                    .test(
                        name: "Product"
                    ),
                ],
                platforms: [.ios],
                cLanguageStandard: nil,
                cxxLanguageStandard: nil,
                swiftLanguageVersions: nil
            ),
        ]
        let packageModuleAliases = [
            "Package2": [
                "Product": "Package2Product",
            ],
        ]
        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: packageInfos,
            packageModuleAliases: packageModuleAliases
        )
        let projectTwo = try await subject.map(
            package: "Package2",
            basePath: basePath,
            packageInfos: packageInfos,
            packageModuleAliases: packageModuleAliases
        )
        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Product",
                            basePath: basePath,
                            dependencies: [
                                .target(name: "Package2Product", condition: nil),
                            ],
                            customSettings: ["OTHER_SWIFT_FLAGS": ["$(inherited)", "-module-alias", "Product=Package2Product"]]
                        ),
                    ]
                )
        )
        #expect(
            projectTwo ==
                .testWithDefaultConfigs(
                    name: "Package2",
                    targets: [
                        .test(
                            "Package2Product",
                            packageName: "Package2",
                            basePath: basePath,
                            customSources: .custom(
                                .sourceFilesList(
                                    globs: [basePath.appending(components: "Package2", "Sources", "Product").pathString + "/**"]
                                )
                            )
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_other_swift_flags_whenSwiftToolsVersionIs_5_8_0() async throws {
        // Given
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/Product")))
        let packageInfos: [String: PackageInfo] = [
            "Package": .test(
                name: "Package",
                products: [
                    .init(name: "Product", type: .library(.automatic), targets: ["Product"]),
                ],
                targets: [
                    .test(
                        name: "Product"
                    ),
                ],
                platforms: [.ios],
                cLanguageStandard: nil,
                cxxLanguageStandard: nil,
                swiftLanguageVersions: nil,
                toolsVersion: Version(5, 8, 0)
            ),
        ]

        // When
        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: packageInfos
        )

        // Then
        #expect(
            project?.targets.first?.settings?.base["OTHER_SWIFT_FLAGS"] ==
                ["$(inherited)"]
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_swift_package_name_whenSwiftToolsVersionIs_5_9_0() async throws {
        // Given
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/Product")))
        let packageInfos: [String: PackageInfo] = [
            "Package": .test(
                name: "Package",
                products: [
                    .init(name: "Product", type: .library(.automatic), targets: ["Product"]),
                ],
                targets: [
                    .test(
                        name: "Product"
                    ),
                ],
                platforms: [.ios],
                cLanguageStandard: nil,
                cxxLanguageStandard: nil,
                swiftLanguageVersions: nil,
                toolsVersion: Version(5, 9, 0)
            ),
        ]

        // When
        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: packageInfos
        )

        // Then
        #expect(
            project?.targets.first?.settings?.base["OTHER_SWIFT_FLAGS"] ==
                .array(["$(inherited)"])
        )
        #expect(project?.targets.first?.settings?.base["SWIFT_PACKAGE_NAME"] == .string("Package"))
        #expect(project?.settings?.base["OTHER_SWIFT_FLAGS"] == nil)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenPackageUsesPackageAccessAndCustomSwiftSettings_addsPackageNameToTargetSettings() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(
            at: basePath.appending(try RelativePath(validating: "SwiftProtobuf/Sources/SwiftProtobuf"))
        )

        let project = try await subject.map(
            package: "SwiftProtobuf",
            basePath: basePath,
            packageInfos: [
                "SwiftProtobuf": .test(
                    name: "SwiftProtobuf",
                    products: [
                        .init(name: "SwiftProtobuf", type: .library(.automatic), targets: ["SwiftProtobuf"]),
                    ],
                    targets: [
                        .test(
                            name: "SwiftProtobuf",
                            settings: [
                                .init(
                                    tool: .swift,
                                    name: .enableUpcomingFeature,
                                    condition: nil,
                                    value: ["ExistentialAny"]
                                ),
                            ]
                        ),
                    ],
                    platforms: [.ios],
                    toolsVersion: Version(5, 9, 0)
                ),
            ]
        )

        let target = try #require(project?.targets.first)
        #expect(
            target.settings?.base["OTHER_SWIFT_FLAGS"] == .array([
                "$(inherited)",
                "-enable-upcoming-feature \"ExistentialAny\"",
            ])
        )
        #expect(target.settings?.base["SWIFT_PACKAGE_NAME"] == .string("SwiftProtobuf"))
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_macroTarget_withCustomSwiftFlags_addsPackageNameToTargetSettings() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(
            at: basePath.appending(try RelativePath(validating: "Package/Sources/MyMacro"))
        )

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [],
                    targets: [
                        .test(name: "MyMacro", type: .macro),
                    ],
                    platforms: [.macos],
                    toolsVersion: Version(5, 9, 0)
                ),
            ],
            packageSettings: .test(
                baseSettings: .default.with(
                    base: ["OTHER_SWIFT_FLAGS": ["-Xfrontend", "-disable-sil-ownership-verifier"]]
                )
            )
        )

        let target = try #require(project?.targets.first(where: { $0.name == "MyMacro" }))
        #expect(
            target.settings?.base["OTHER_SWIFT_FLAGS"] == .array([
                "-Xfrontend",
                "-disable-sil-ownership-verifier",
            ])
        )
        #expect(target.settings?.base["SWIFT_PACKAGE_NAME"] == .string("Package"))
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenSourcesDirectlyInSourcesDirectory_SE0162Support() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let packagePath = basePath.appending(try RelativePath(validating: "Package"))
        let sourcesPath = packagePath.appending(try RelativePath(validating: "Sources"))

        try await fileSystem.makeDirectory(at: sourcesPath)
        try await fileSystem.touch(sourcesPath.appending(component: "Target1.swift"))
        try await fileSystem.touch(sourcesPath.appending(component: "Helper.swift"))
        try await fileSystem.touch(sourcesPath.appending(component: "Utils.swift"))

        let packageInfo = PackageInfo.test(
            name: "Package",
            products: [
                .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
            ],
            targets: [
                .test(
                    name: "Target1",
                    path: nil,
                    sources: nil,
                    type: .regular
                ),
            ],
            platforms: [.ios],
            cLanguageStandard: nil,
            cxxLanguageStandard: nil,
            swiftLanguageVersions: nil
        )

        let project = try await subject.map(
            packageInfo: packageInfo,
            path: packagePath,
            packageType: .local,
            packageSettings: .test(),
            packageModuleAliases: [:],
            packageProducts: [:],
            enabledTraits: []
        )

        #expect(project != nil)
        #expect(project?.targets.count == 1)

        let target = project?.targets.first
        #expect(target?.name == "Target1")

        let sources = target?.sources
        #expect(sources?.globs.count ?? 0 > 0)
        let firstGlob = sources?.globs.first
        #expect(firstGlob?.glob.pathString.contains("Package/Sources/**") == true)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenNoSourcesFound_throwsError() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let packagePath = basePath.appending(try RelativePath(validating: "Package"))

        let packageInfo = PackageInfo.test(
            name: "Package",
            products: [
                .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
            ],
            targets: [
                .test(
                    name: "Target1",
                    path: nil,
                    sources: nil,
                    type: .regular
                ),
            ],
            platforms: [.ios]
        )

        await #expect(throws: PackageInfoMapperError.self) {
            _ = try await subject.map(
                packageInfo: packageInfo,
                path: packagePath,
                packageType: .local,
                packageSettings: .test(),
                packageModuleAliases: [:],
                packageProducts: [:],
                enabledTraits: []
            )
        }
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenMixedCAndSwiftSources_detectsProperly() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let packagePath = basePath.appending(try RelativePath(validating: "Package"))
        let sourcesPath = packagePath.appending(try RelativePath(validating: "Sources"))

        try await fileSystem.makeDirectory(at: sourcesPath)
        try await fileSystem.touch(sourcesPath.appending(component: "main.swift"))
        try await fileSystem.touch(sourcesPath.appending(component: "helper.c"))
        try await fileSystem.touch(sourcesPath.appending(component: "helper.h"))

        let packageInfo = PackageInfo.test(
            name: "Package",
            products: [
                .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
            ],
            targets: [
                .test(
                    name: "Target1",
                    path: nil,
                    sources: nil,
                    type: .regular
                ),
            ],
            platforms: [.ios]
        )

        let project = try await subject.map(
            packageInfo: packageInfo,
            path: packagePath,
            packageType: .local,
            packageSettings: .test(),
            packageModuleAliases: [:],
            packageProducts: [:],
            enabledTraits: []
        )

        #expect(project != nil)
        let target = project?.targets.first
        #expect(target?.name == "Target1")

        let sources = target?.sources
        #expect(sources?.globs.count ?? 0 > 0)
        let firstGlob = sources?.globs.first
        #expect(firstGlob?.glob.pathString.contains("Package/Sources/**") == true)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenTestTargetWithCustomLayout_SE0162Support() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let packagePath = basePath.appending(try RelativePath(validating: "Package"))
        let testsPath = packagePath.appending(try RelativePath(validating: "Tests"))

        try await fileSystem.makeDirectory(at: testsPath)
        try await fileSystem.touch(testsPath.appending(component: "PackageTests.swift"))
        try await fileSystem.touch(testsPath.appending(component: "HelperTests.swift"))

        let packageInfo = PackageInfo.test(
            name: "Package",
            products: [],
            targets: [
                .test(
                    name: "PackageTests",
                    path: nil,
                    sources: nil,
                    type: .test
                ),
            ],
            platforms: [.ios]
        )

        let project = try await subject.map(
            packageInfo: packageInfo,
            path: packagePath,
            packageType: .local,
            packageSettings: .test(),
            packageModuleAliases: [:],
            packageProducts: [:],
            enabledTraits: []
        )

        #expect(project != nil)
        #expect(project?.targets.count == 1)

        let target = project?.targets.first
        #expect(target?.name == "PackageTests")
        #expect(target?.product == .unitTests)

        let sources = target?.sources
        #expect(sources?.globs.count ?? 0 > 0)
        let firstGlob = sources?.globs.first
        #expect(firstGlob?.glob.pathString.contains("Package/Tests/**") == true)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenAlternativeSourceDirectory_SE0162Support() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let packagePath = basePath.appending(try RelativePath(validating: "Package"))
        let sourcePath = packagePath.appending(try RelativePath(validating: "Source"))

        try await fileSystem.makeDirectory(at: sourcePath)
        try await fileSystem.touch(sourcePath.appending(component: "Main.swift"))
        try await fileSystem.touch(sourcePath.appending(component: "Utils.swift"))

        let packageInfo = PackageInfo.test(
            name: "Package",
            products: [
                .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
            ],
            targets: [
                .test(
                    name: "Target1",
                    path: nil,
                    sources: nil,
                    type: .regular
                ),
            ],
            platforms: [.ios]
        )

        let project = try await subject.map(
            packageInfo: packageInfo,
            path: packagePath,
            packageType: .local,
            packageSettings: .test(),
            packageModuleAliases: [:],
            packageProducts: [:],
            enabledTraits: []
        )

        #expect(project != nil)
        let target = project?.targets.first
        #expect(target?.name == "Target1")

        let sources = target?.sources
        #expect(sources?.globs.count ?? 0 > 0)
        let firstGlob = sources?.globs.first
        #expect(firstGlob?.glob.pathString.contains("Package/Source/**") == true)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenSourcesDirectoryExistsButEmpty_fallsBackToStandardLayout() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let packagePath = basePath.appending(try RelativePath(validating: "Package"))
        let sourcesPath = packagePath.appending(try RelativePath(validating: "Sources"))
        let targetPath = packagePath.appending(try RelativePath(validating: "Sources/Target1"))

        // Sources/ exists but is empty, files are in Sources/Target1/
        try await fileSystem.makeDirectory(at: sourcesPath)
        try await fileSystem.makeDirectory(at: targetPath)
        try await fileSystem.touch(targetPath.appending(component: "File.swift"))

        let packageInfo = PackageInfo.test(
            name: "Package",
            products: [
                .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
            ],
            targets: [
                .test(
                    name: "Target1",
                    path: nil,
                    sources: nil,
                    type: .regular
                ),
            ],
            platforms: [.ios]
        )

        let project = try await subject.map(
            packageInfo: packageInfo,
            path: packagePath,
            packageType: .local,
            packageSettings: .test(),
            packageModuleAliases: [:],
            packageProducts: [:],
            enabledTraits: []
        )

        #expect(project != nil)
        let target = project?.targets.first
        #expect(target?.name == "Target1")

        let sources = target?.sources
        #expect(sources?.globs.count ?? 0 > 0)
        let firstGlob = sources?.globs.first
        // Should use standard layout, not SE-0162 layout
        #expect(firstGlob?.glob.pathString.contains("Package/Sources/Target1/**") == true)
    }

    // MARK: - Enabled Traits Tests

    @Test(.withMockedSwiftVersionProvider)
    func enabledTraits_whenRootPackageHasUnconditionalTraits_returnsTraitsForDependency() {
        let rootPackageInfo = PackageInfo.test(
            name: "RootPackage",
            products: [],
            targets: [],
            dependencies: [
                PackageDependency(
                    identity: "dependency-a",
                    traits: [
                        PackageDependencyTrait(name: "FeatureX", condition: nil),
                        PackageDependencyTrait(name: "FeatureY", condition: nil),
                    ]
                ),
            ]
        )

        let result = SwiftPackageManagerGraphLoader.enabledTraits(
            rootPackageInfo: rootPackageInfo,
            packageInfos: [:]
        )

        #expect(result["dependency-a"] == Set(["FeatureX", "FeatureY"]))
    }

    @Test(.withMockedSwiftVersionProvider)
    func enabledTraits_whenNoTraitsSpecified_returnsEmptyDictionary() {
        let rootPackageInfo = PackageInfo.test(
            name: "RootPackage",
            products: [],
            targets: [],
            dependencies: [
                PackageDependency(identity: "dependency-a", traits: []),
            ]
        )

        let result = SwiftPackageManagerGraphLoader.enabledTraits(
            rootPackageInfo: rootPackageInfo,
            packageInfos: [:]
        )

        #expect(result.isEmpty)
    }

    @Test(.withMockedSwiftVersionProvider)
    func enabledTraits_whenDependencyUsesDefaultTrait_resolvesUnderlyingTraits() {
        let rootPackageInfo = PackageInfo.test(
            name: "RootPackage",
            products: [],
            targets: [],
            dependencies: [
                PackageDependency(
                    identity: "hummingbird",
                    traits: [PackageDependencyTrait(name: "default")]
                ),
            ]
        )

        let hummingbirdInfo = PackageInfo.test(
            name: "hummingbird",
            products: [],
            targets: [],
            traits: [
                PackageTrait(
                    enabledTraits: ["ConfigurationSupport"],
                    name: "default",
                    description: "The default traits of this package."
                ),
                PackageTrait(
                    enabledTraits: [],
                    name: "ConfigurationSupport",
                    description: "Enable support for swift-configuration package."
                ),
            ]
        )

        let result = SwiftPackageManagerGraphLoader.enabledTraits(
            rootPackageInfo: rootPackageInfo,
            packageInfos: ["hummingbird": hummingbirdInfo]
        )

        #expect(result["hummingbird"] == Set(["default", "ConfigurationSupport"]))
    }

    @Test(.withMockedSwiftVersionProvider)
    func enabledTraits_whenDependencyExplicitlyDisablesTraits_doesNotEnableDefaultTraits() {
        let rootPackageInfo = PackageInfo.test(
            name: "RootPackage",
            products: [],
            targets: [],
            dependencies: [
                PackageDependency(identity: "hummingbird", traits: []),
            ]
        )

        let hummingbirdInfo = PackageInfo.test(
            name: "hummingbird",
            products: [],
            targets: [],
            traits: [
                PackageTrait(
                    enabledTraits: ["ConfigurationSupport"],
                    name: "default",
                    description: "The default traits of this package."
                ),
                PackageTrait(
                    enabledTraits: [],
                    name: "ConfigurationSupport",
                    description: "Enable support for swift-configuration package."
                ),
            ]
        )

        let result = SwiftPackageManagerGraphLoader.enabledTraits(
            rootPackageInfo: rootPackageInfo,
            packageInfos: ["hummingbird": hummingbirdInfo]
        )

        #expect(result["hummingbird"] == nil)
    }

    @Test(.withMockedSwiftVersionProvider)
    func enabledTraits_whenConditionalTraitWithMatchingCondition_enablesTrait() {
        let rootPackageInfo = PackageInfo.test(
            name: "RootPackage",
            products: [],
            targets: [],
            dependencies: [
                PackageDependency(
                    identity: "dependency-a",
                    traits: [PackageDependencyTrait(name: "FeatureX", condition: nil)]
                ),
            ]
        )

        let dependencyAInfo = PackageInfo.test(
            name: "DependencyA",
            products: [],
            targets: [],
            traits: [
                PackageTrait(enabledTraits: [], name: "FeatureX", description: nil),
            ],
            dependencies: [
                PackageDependency(
                    identity: "dependency-b",
                    traits: [PackageDependencyTrait(name: "ConditionalFeature", condition: Set(["FeatureX"]))]
                ),
            ]
        )

        let result = SwiftPackageManagerGraphLoader.enabledTraits(
            rootPackageInfo: rootPackageInfo,
            packageInfos: ["dependency-a": dependencyAInfo]
        )

        #expect(result["dependency-a"] == Set(["FeatureX"]))
        #expect(result["dependency-b"] == Set(["ConditionalFeature"]))
    }

    @Test(.withMockedSwiftVersionProvider)
    func enabledTraits_whenConditionalTraitWithNonMatchingCondition_doesNotEnableTrait() {
        let rootPackageInfo = PackageInfo.test(
            name: "RootPackage",
            products: [],
            targets: [],
            dependencies: [
                PackageDependency(
                    identity: "dependency-a",
                    traits: [PackageDependencyTrait(name: "FeatureX", condition: nil)]
                ),
            ]
        )

        let dependencyAInfo = PackageInfo.test(
            name: "DependencyA",
            products: [],
            targets: [],
            traits: [
                PackageTrait(enabledTraits: [], name: "FeatureX", description: nil),
                PackageTrait(enabledTraits: [], name: "FeatureY", description: nil),
            ],
            dependencies: [
                PackageDependency(
                    identity: "dependency-b",
                    traits: [PackageDependencyTrait(name: "ConditionalFeature", condition: Set(["FeatureY"]))]
                ),
            ]
        )

        let result = SwiftPackageManagerGraphLoader.enabledTraits(
            rootPackageInfo: rootPackageInfo,
            packageInfos: ["dependency-a": dependencyAInfo]
        )

        #expect(result["dependency-a"] == Set(["FeatureX"]))
        #expect(result["dependency-b"] == nil)
    }

    @Test(.withMockedSwiftVersionProvider)
    func enabledTraits_whenMultipleDependenciesWithTraits_aggregatesCorrectly() {
        let rootPackageInfo = PackageInfo.test(
            name: "RootPackage",
            products: [],
            targets: [],
            dependencies: [
                PackageDependency(
                    identity: "dependency-a",
                    traits: [PackageDependencyTrait(name: "FeatureA", condition: nil)]
                ),
                PackageDependency(
                    identity: "dependency-b",
                    traits: [
                        PackageDependencyTrait(name: "FeatureB1", condition: nil),
                        PackageDependencyTrait(name: "FeatureB2", condition: nil),
                    ]
                ),
            ]
        )

        let result = SwiftPackageManagerGraphLoader.enabledTraits(
            rootPackageInfo: rootPackageInfo,
            packageInfos: [:]
        )

        #expect(result["dependency-a"] == Set(["FeatureA"]))
        #expect(result["dependency-b"] == Set(["FeatureB1", "FeatureB2"]))
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenEnabledTraits_setsSwiftActiveCompilationConditions() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let packagePath = basePath.appending(component: "Package")
        let targetPath = packagePath.appending(components: "Sources", "Target1")
        try await fileSystem.makeDirectory(at: targetPath)
        try await fileSystem.touch(targetPath.appending(component: "File.swift"))

        let packageInfo = PackageInfo.test(
            name: "Package",
            products: [
                .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
            ],
            targets: [
                .test(name: "Target1", type: .regular),
            ],
            traits: [
                PackageTrait(enabledTraits: [], name: "FeatureX", description: "Feature X"),
                PackageTrait(enabledTraits: [], name: "FeatureY", description: "Feature Y"),
            ],
            platforms: [.ios]
        )

        let project = try await subject.map(
            packageInfo: packageInfo,
            path: packagePath,
            packageType: .local,
            packageSettings: .test(),
            packageModuleAliases: [:],
            packageProducts: [:],
            enabledTraits: Set(["FeatureX", "FeatureY"])
        )

        #expect(project != nil)
        let target = try #require(project?.targets.first)
        let settings = target.settings
        let baseSettings = settings?.base
        let swiftConditions = baseSettings?["SWIFT_ACTIVE_COMPILATION_CONDITIONS"]

        #expect(swiftConditions == .array(["$(inherited)", "FeatureX", "FeatureY"]))
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenDefaultTraitEnabled_resolvesToEnabledTraits() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let packagePath = basePath.appending(component: "Package")
        let targetPath = packagePath.appending(components: "Sources", "Target1")
        try await fileSystem.makeDirectory(at: targetPath)
        try await fileSystem.touch(targetPath.appending(component: "File.swift"))

        let packageInfo = PackageInfo.test(
            name: "Package",
            products: [
                .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
            ],
            targets: [
                .test(name: "Target1", type: .regular),
            ],
            traits: [
                PackageTrait(enabledTraits: ["ActualFeature"], name: "default", description: "Default trait"),
                PackageTrait(enabledTraits: [], name: "ActualFeature", description: "The actual feature"),
            ],
            platforms: [.ios]
        )

        let project = try await subject.map(
            packageInfo: packageInfo,
            path: packagePath,
            packageType: .local,
            packageSettings: .test(),
            packageModuleAliases: [:],
            packageProducts: [:],
            enabledTraits: Set(["default"])
        )

        #expect(project != nil)
        let target = try #require(project?.targets.first)
        let settings = target.settings
        let baseSettings = settings?.base
        let swiftConditions = baseSettings?["SWIFT_ACTIVE_COMPILATION_CONDITIONS"]

        #expect(swiftConditions == .array(["$(inherited)", "ActualFeature"]))
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenDependencyUsesDefaultTrait_includesHummingbirdConfigurationDependency() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem
            .makeDirectory(at: basePath.appending(try RelativePath(validating: "hummingbird/Sources/HummingbirdCore")))
        try await fileSystem.touch(
            basePath
                .appending(try RelativePath(validating: "hummingbird/Sources/HummingbirdCore/HTTP1Channel+ConfigReader.swift"))
        )
        try await fileSystem.makeDirectory(
            at: basePath.appending(try RelativePath(validating: "swift-configuration/Sources/Configuration"))
        )
        try await fileSystem.touch(
            basePath.appending(try RelativePath(validating: "swift-configuration/Sources/Configuration/Configuration.swift"))
        )

        let rootPackageInfo = PackageInfo.test(
            name: "RootPackage",
            products: [],
            targets: [],
            dependencies: [
                PackageDependency(
                    identity: "hummingbird",
                    traits: [PackageDependencyTrait(name: "default")]
                ),
            ]
        )

        let hummingbirdInfo = PackageInfo.test(
            name: "hummingbird",
            products: [
                .init(name: "Hummingbird", type: .library(.automatic), targets: ["HummingbirdCore"]),
            ],
            targets: [
                .test(
                    name: "HummingbirdCore",
                    dependencies: [
                        .product(
                            name: "Configuration",
                            package: "swift-configuration",
                            moduleAliases: nil,
                            condition: .init(platformNames: [], config: nil, traits: ["ConfigurationSupport"])
                        ),
                    ]
                ),
            ],
            traits: [
                PackageTrait(
                    enabledTraits: ["ConfigurationSupport"],
                    name: "default",
                    description: "The default traits of this package."
                ),
                PackageTrait(
                    enabledTraits: [],
                    name: "ConfigurationSupport",
                    description: "Enable support for swift-configuration package."
                ),
            ],
            platforms: [.ios]
        )
        let swiftConfigurationInfo = PackageInfo.test(
            name: "swift-configuration",
            products: [
                .init(name: "Configuration", type: .library(.automatic), targets: ["Configuration"]),
            ],
            targets: [
                .test(name: "Configuration"),
            ],
            platforms: [.ios]
        )

        let packageInfos = [
            "hummingbird": hummingbirdInfo,
            "swift-configuration": swiftConfigurationInfo,
        ]
        let activeTraits = SwiftPackageManagerGraphLoader.enabledTraits(
            rootPackageInfo: rootPackageInfo,
            packageInfos: packageInfos
        )

        #expect(activeTraits["hummingbird"] == Set(["default", "ConfigurationSupport"]))

        let project = try await subject.map(
            package: "hummingbird",
            basePath: basePath,
            packageInfos: packageInfos,
            enabledTraits: activeTraits["hummingbird"] ?? []
        )

        let target = try #require(project?.targets.first(where: { $0.name == "HummingbirdCore" }))
        #expect(target.dependencies.count == 1)
        #expect(target.dependencies.first == .external(name: "Configuration"))

        let swiftConditions = target.settings?.base["SWIFT_ACTIVE_COMPILATION_CONDITIONS"]
        #expect(swiftConditions == .array(["$(inherited)", "ConfigurationSupport"]))
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenNoTraitsEnabled_doesNotSetSwiftActiveCompilationConditions() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let packagePath = basePath.appending(component: "Package")
        let targetPath = packagePath.appending(components: "Sources", "Target1")
        try await fileSystem.makeDirectory(at: targetPath)
        try await fileSystem.touch(targetPath.appending(component: "File.swift"))

        let packageInfo = PackageInfo.test(
            name: "Package",
            products: [
                .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
            ],
            targets: [
                .test(name: "Target1", type: .regular),
            ],
            traits: [
                PackageTrait(enabledTraits: [], name: "FeatureX", description: "Feature X"),
            ],
            platforms: [.ios]
        )

        let project = try await subject.map(
            packageInfo: packageInfo,
            path: packagePath,
            packageType: .local,
            packageSettings: .test(),
            packageModuleAliases: [:],
            packageProducts: [:],
            enabledTraits: []
        )

        #expect(project != nil)
        let target = try #require(project?.targets.first)
        let settings = target.settings
        let baseSettings = settings?.base
        let swiftConditions = baseSettings?["SWIFT_ACTIVE_COMPILATION_CONDITIONS"]

        #expect(swiftConditions == nil)
    }

    // MARK: - Trait Condition Filtering Tests

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenDependencyHasTraitConditionAndTraitNotEnabled_excludesDependency() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/Target1")))
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package2/Sources/Target2")))

        let package1 = PackageInfo.test(
            name: "Package",
            products: [
                .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
            ],
            targets: [
                .test(
                    name: "Target1",
                    dependencies: [
                        .product(
                            name: "Product2",
                            package: "Package2",
                            moduleAliases: nil,
                            condition: .init(platformNames: [], config: nil, traits: ["FeatureX"])
                        ),
                    ]
                ),
            ],
            traits: [
                PackageTrait(enabledTraits: [], name: "FeatureX", description: "Feature X"),
            ],
            platforms: [.ios]
        )
        let package2 = PackageInfo.test(
            name: "Package2",
            products: [
                .init(name: "Product2", type: .library(.automatic), targets: ["Target2"]),
            ],
            targets: [
                .test(name: "Target2"),
            ],
            platforms: [.ios]
        )

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: ["Package": package1, "Package2": package2],
            enabledTraits: []
        )

        let target = try #require(project?.targets.first(where: { $0.name == "Target1" }))
        #expect(target.dependencies.isEmpty)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenDependencyHasTraitConditionAndTraitEnabled_includesDependency() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/Target1")))
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package2/Sources/Target2")))

        let package1 = PackageInfo.test(
            name: "Package",
            products: [
                .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
            ],
            targets: [
                .test(
                    name: "Target1",
                    dependencies: [
                        .product(
                            name: "Product2",
                            package: "Package2",
                            moduleAliases: nil,
                            condition: .init(platformNames: [], config: nil, traits: ["FeatureX"])
                        ),
                    ]
                ),
            ],
            traits: [
                PackageTrait(enabledTraits: [], name: "FeatureX", description: "Feature X"),
            ],
            platforms: [.ios]
        )
        let package2 = PackageInfo.test(
            name: "Package2",
            products: [
                .init(name: "Product2", type: .library(.automatic), targets: ["Target2"]),
            ],
            targets: [
                .test(name: "Target2"),
            ],
            platforms: [.ios]
        )

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: ["Package": package1, "Package2": package2],
            enabledTraits: Set(["FeatureX"])
        )

        let target = try #require(project?.targets.first(where: { $0.name == "Target1" }))
        #expect(target.dependencies.count == 1)
        #expect(target.dependencies.first == .external(name: "Product2"))
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenDependencyHasMultipleTraitConditionsAndOneEnabled_includesDependency() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/Target1")))
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package2/Sources/Target2")))

        let package1 = PackageInfo.test(
            name: "Package",
            products: [
                .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
            ],
            targets: [
                .test(
                    name: "Target1",
                    dependencies: [
                        .product(
                            name: "Product2",
                            package: "Package2",
                            moduleAliases: nil,
                            condition: .init(platformNames: [], config: nil, traits: ["FeatureX", "FeatureY"])
                        ),
                    ]
                ),
            ],
            traits: [
                PackageTrait(enabledTraits: [], name: "FeatureX", description: "Feature X"),
                PackageTrait(enabledTraits: [], name: "FeatureY", description: "Feature Y"),
            ],
            platforms: [.ios]
        )
        let package2 = PackageInfo.test(
            name: "Package2",
            products: [
                .init(name: "Product2", type: .library(.automatic), targets: ["Target2"]),
            ],
            targets: [
                .test(name: "Target2"),
            ],
            platforms: [.ios]
        )

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: ["Package": package1, "Package2": package2],
            enabledTraits: Set(["FeatureY"])
        )

        let target = try #require(project?.targets.first(where: { $0.name == "Target1" }))
        #expect(target.dependencies.count == 1)
        #expect(target.dependencies.first == .external(name: "Product2"))
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenDependencyHasNoTraitCondition_includesDependency() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/Target1")))
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package2/Sources/Target2")))

        let package1 = PackageInfo.test(
            name: "Package",
            products: [
                .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
            ],
            targets: [
                .test(
                    name: "Target1",
                    dependencies: [
                        .product(
                            name: "Product2",
                            package: "Package2",
                            moduleAliases: nil,
                            condition: nil
                        ),
                    ]
                ),
            ],
            platforms: [.ios]
        )
        let package2 = PackageInfo.test(
            name: "Package2",
            products: [
                .init(name: "Product2", type: .library(.automatic), targets: ["Target2"]),
            ],
            targets: [
                .test(name: "Target2"),
            ],
            platforms: [.ios]
        )

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: ["Package": package1, "Package2": package2],
            enabledTraits: []
        )

        let target = try #require(project?.targets.first(where: { $0.name == "Target1" }))
        #expect(target.dependencies.count == 1)
        #expect(target.dependencies.first == .external(name: "Product2"))
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenTargetDependencyHasTraitConditionAndTraitNotEnabled_excludesDependency() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/Target1")))
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/Target2")))

        let package = PackageInfo.test(
            name: "Package",
            products: [
                .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
            ],
            targets: [
                .test(
                    name: "Target1",
                    dependencies: [
                        .target(
                            name: "Target2",
                            condition: .init(platformNames: [], config: nil, traits: ["FeatureX"])
                        ),
                    ]
                ),
                .test(name: "Target2"),
            ],
            traits: [
                PackageTrait(enabledTraits: [], name: "FeatureX", description: "Feature X"),
            ],
            platforms: [.ios]
        )

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: ["Package": package],
            enabledTraits: []
        )

        let target = try #require(project?.targets.first(where: { $0.name == "Target1" }))
        #expect(target.dependencies.isEmpty)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func map_whenByNameDependencyHasTraitConditionAndTraitNotEnabled_excludesDependency() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/Target1")))
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/Target2")))

        let package = PackageInfo.test(
            name: "Package",
            products: [
                .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
            ],
            targets: [
                .test(
                    name: "Target1",
                    dependencies: [
                        .byName(
                            name: "Target2",
                            condition: .init(platformNames: [], config: nil, traits: ["FeatureX"])
                        ),
                    ]
                ),
                .test(name: "Target2"),
            ],
            traits: [
                PackageTrait(enabledTraits: [], name: "FeatureX", description: "Feature X"),
            ],
            platforms: [.ios]
        )

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: ["Package": package],
            enabledTraits: []
        )

        let target = try #require(project?.targets.first(where: { $0.name == "Target1" }))
        #expect(target.dependencies.isEmpty)
    }

    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_whenWrapperTargetPattern_usesProductNameAsModuleName() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/ATarget")))

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "A", type: .library(.automatic), targets: ["ATarget"]),
                    ],
                    targets: [
                        .test(name: "ATarget"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        let mappedTarget = try #require(project?.targets.first(where: { $0.name == "ATarget" }))
        #expect(mappedTarget.productName == "A")
    }

    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_whenWrapperTargetPattern_productTypesLookedUpByProductName() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/ATarget")))

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "A", type: .library(.automatic), targets: ["ATarget"]),
                    ],
                    targets: [
                        .test(name: "ATarget"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ],
            packageSettings: .test(
                productTypes: ["A": .framework],
                baseSettings: .default
            )
        )
        let mappedTarget = try #require(project?.targets.first(where: { $0.name == "ATarget" }))
        #expect(mappedTarget.product == .framework)
    }

    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_whenWrapperTargetPattern_baseProductTypeUsed() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/ATarget")))

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "A", type: .library(.automatic), targets: ["ATarget"]),
                    ],
                    targets: [
                        .test(name: "ATarget"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ],
            packageSettings: .test(
                baseProductType: .framework
            )
        )
        let mappedTarget = try #require(project?.targets.first(where: { $0.name == "ATarget" }))
        #expect(mappedTarget.product == .framework)
    }

    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_whenSameNameProductAndTarget_keepsTargetNameAsProductName() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/Foo")))

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Foo", type: .library(.automatic), targets: ["Foo"]),
                    ],
                    targets: [
                        .test(name: "Foo"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        let mappedTarget = try #require(project?.targets.first(where: { $0.name == "Foo" }))
        #expect(mappedTarget.productName == "Foo")
    }

    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_whenWrapperTargetDependsOnBinaryTarget_keepsTargetNameAsProductName() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(
            at: basePath.appending(try RelativePath(validating: "Package/Sources/GoogleMapsTarget"))
        )

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "GoogleMaps", type: .library(.automatic), targets: ["GoogleMapsTarget"]),
                    ],
                    targets: [
                        .test(
                            name: "GoogleMapsTarget",
                            dependencies: [.target(name: "GoogleMaps", condition: nil)]
                        ),
                        .test(name: "GoogleMaps", type: .binary),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        let mappedTarget = try #require(project?.targets.first(where: { $0.name == "GoogleMapsTarget" }))
        #expect(mappedTarget.productName == "GoogleMapsTarget")
    }

    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_whenWrapperTargetDependsTransitivelyOnBinaryTarget_keepsTargetNameAsProductName() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(
            at: basePath.appending(try RelativePath(validating: "Package/Sources/FirebaseAnalyticsTarget"))
        )
        try await fileSystem.makeDirectory(
            at: basePath.appending(try RelativePath(validating: "Package/Sources/FirebaseAnalyticsWrapper"))
        )

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "FirebaseAnalytics", type: .library(.automatic), targets: ["FirebaseAnalyticsTarget"]),
                    ],
                    targets: [
                        .test(
                            name: "FirebaseAnalyticsTarget",
                            dependencies: [
                                .target(name: "FirebaseAnalyticsWrapper", condition: nil),
                            ]
                        ),
                        .test(
                            name: "FirebaseAnalyticsWrapper",
                            dependencies: [.target(name: "FirebaseAnalytics", condition: nil)]
                        ),
                        .test(name: "FirebaseAnalytics", type: .binary),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        let mappedTarget = try #require(project?.targets.first(where: { $0.name == "FirebaseAnalyticsTarget" }))
        #expect(mappedTarget.productName == "FirebaseAnalyticsTarget")
    }

    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_whenTransitiveTargetMatchesProductPrefix_keepsOwnTargetNameAsProductName() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/Sharing")))
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/Sharing1")))
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/Sharing2")))

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Sharing", type: .library(.automatic), targets: ["Sharing"]),
                    ],
                    targets: [
                        .test(
                            name: "Sharing",
                            dependencies: [
                                .target(name: "Sharing1", condition: nil),
                                .target(name: "Sharing2", condition: nil),
                            ]
                        ),
                        .test(name: "Sharing1"),
                        .test(name: "Sharing2"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        let sharing1Target = try #require(project?.targets.first(where: { $0.name == "Sharing1" }))
        let sharing2Target = try #require(project?.targets.first(where: { $0.name == "Sharing2" }))
        #expect(sharing1Target.productName == "Sharing1")
        #expect(sharing2Target.productName == "Sharing2")
    }

    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_whenMultiTargetProduct_keepsOwnTargetNameAsProductName() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/FooCore")))
        try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: "Package/Sources/FooUI")))

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Foo", type: .library(.automatic), targets: ["FooCore", "FooUI"]),
                    ],
                    targets: [
                        .test(name: "FooCore"),
                        .test(name: "FooUI"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        let fooCoreTarget = try #require(project?.targets.first(where: { $0.name == "FooCore" }))
        let fooUITarget = try #require(project?.targets.first(where: { $0.name == "FooUI" }))
        #expect(fooCoreTarget.productName == "FooCore")
        #expect(fooUITarget.productName == "FooUI")
    }

    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_whenBinaryTargetXcframeworkBaseNameMatchesProductName_keepsTargetNameAsProductName() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(
            at: basePath.appending(try RelativePath(validating: "Package/Sources/MySDK_Facade"))
        )

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "MySDK", type: .library(.static), targets: ["MySDK_Facade"]),
                    ],
                    targets: [
                        .test(
                            name: "MySDK_Facade",
                            dependencies: [
                                .target(name: "MySDK_Static", condition: nil),
                            ]
                        ),
                        .test(
                            name: "MySDK_Static",
                            type: .binary,
                            path: "Frameworks/Static/MySDK.xcframework"
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        let mappedTarget = try #require(project?.targets.first(where: { $0.name == "MySDK_Facade" }))
        #expect(mappedTarget.productName == "MySDK_Facade")
    }

    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_whenRemoteBinaryTargetNameMatchesProductPrefix_keepsTargetNameAsProductName() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(
            at: basePath.appending(try RelativePath(validating: "Package/Sources/NMapsMapTarget"))
        )

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "NMapsMap", type: .library(.automatic), targets: ["NMapsMapTarget"]),
                    ],
                    targets: [
                        .test(
                            name: "NMapsMapTarget",
                            dependencies: [
                                .target(name: "NMapsMapBinary", condition: nil),
                            ]
                        ),
                        .test(
                            name: "NMapsMapBinary",
                            type: .binary,
                            url: "https://repository.map.naver.com/archive/pod/NMapsMap/3.23.1/NMapsMap.zip"
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )

        let mappedTarget = try #require(project?.targets.first(where: { $0.name == "NMapsMapTarget" }))
        #expect(mappedTarget.productName == "NMapsMapTarget")
    }

    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_whenUnderscorePrefixedBinaryTargetMatchesProductName_keepsTargetNameAsProductName() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(
            at: basePath.appending(try RelativePath(validating: "Package/Sources/FirebaseCrashlyticsTarget"))
        )

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(
                            name: "FirebaseCrashlytics",
                            type: .library(.automatic),
                            targets: ["FirebaseCrashlyticsTarget"]
                        ),
                    ],
                    targets: [
                        .test(
                            name: "FirebaseCrashlyticsTarget",
                            dependencies: [
                                .target(name: "_FirebaseCrashlytics", condition: nil),
                            ]
                        ),
                        .test(
                            name: "_FirebaseCrashlytics",
                            type: .binary,
                            url: "https://github.com/akaffenberger/firebase-ios-sdk-xcframeworks/releases/download/11.15.0/_FirebaseCrashlytics.xcframework.zip"
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )

        let mappedTarget = try #require(project?.targets.first(where: { $0.name == "FirebaseCrashlyticsTarget" }))
        #expect(mappedTarget.productName == "FirebaseCrashlyticsTarget")
    }

    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_addsSwiftBackDeploymentLibrariesToRunpathSearchPaths() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(
            at: basePath.appending(try RelativePath(validating: "Package/Sources/Library"))
        )

        let backDeploymentProvider = MockSwiftBackDeploymentLibrariesProviding()
        given(backDeploymentProvider)
            .runpathSearchPaths()
            .willReturn(["$(TOOLCHAIN_DIR)/usr/lib/swift-test/$(PLATFORM_NAME)"])

        let project = try await SwiftBackDeploymentLibrariesProvider.$current.withValue(backDeploymentProvider) {
            try await subject.map(
                package: "Package",
                basePath: basePath,
                packageInfos: [
                    "Package": .test(
                        name: "Package",
                        products: [
                            .init(name: "Library", type: .library(.automatic), targets: ["Library"]),
                        ],
                        targets: [
                            .test(name: "Library"),
                        ],
                        platforms: [.ios],
                        cLanguageStandard: nil,
                        cxxLanguageStandard: nil,
                        swiftLanguageVersions: nil
                    ),
                ]
            )
        }

        let mappedTarget = try #require(project?.targets.first(where: { $0.name == "Library" }))
        #expect(
            mappedTarget.settings?.base["LD_RUNPATH_SEARCH_PATHS"] == .array([
                "$(inherited)",
                "$(TOOLCHAIN_DIR)/usr/lib/swift-test/$(PLATFORM_NAME)",
            ])
        )
    }

    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_whenWrapperTargetSharesProductNameWithBinaryXcframework_suffixesProductName() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(
            at: basePath.appending(try RelativePath(validating: "Package/Sources/Singular"))
        )

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Singular",
                    products: [
                        .init(name: "Singular", type: .library(.automatic), targets: ["Singular"]),
                    ],
                    targets: [
                        .test(
                            name: "Singular",
                            dependencies: [
                                .target(name: "SingularBinary", condition: nil),
                            ]
                        ),
                        .test(
                            name: "SingularBinary",
                            type: .binary,
                            path: "Singular.xcframework"
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )

        let mappedTarget = try #require(project?.targets.first(where: { $0.name == "Singular" }))
        #expect(mappedTarget.productName == "SingularWrapper")
        #expect(mappedTarget.settings?.base["PRODUCT_MODULE_NAME"] == .string("Singular"))
    }

    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_whenWrapperTargetSharesProductNameWithBinaryXcframework_keepsOriginalModuleNameInModuleMap() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let headersPath = basePath.appending(try RelativePath(validating: "Package/Sources/Singular/include"))
        let headerPath = headersPath.appending(component: "Singular.h")

        try await fileSystem.makeDirectory(at: headersPath)
        try await fileSystem.writeText("", at: headerPath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Singular",
                    products: [
                        .init(name: "Singular", type: .library(.automatic), targets: ["Singular"]),
                    ],
                    targets: [
                        .test(
                            name: "Singular",
                            dependencies: [
                                .target(name: "SingularBinary", condition: nil),
                            ]
                        ),
                        .test(
                            name: "SingularBinary",
                            type: .binary,
                            path: "Singular.xcframework"
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )

        #expect(
            project ==
                .testWithDefaultConfigs(
                    name: "Singular",
                    targets: [
                        .test(
                            "Singular",
                            swiftPackageName: "Singular",
                            basePath: basePath,
                            customProductName: "SingularWrapper",
                            headers: .spmTarget(
                                headersPath.parentDirectory,
                                moduleMap: basePath.appending(components: "Package", "Derived", "Singular.modulemap")
                            ),
                            dependencies: [.xcframework(path: .path(
                                basePath
                                    .appending(try RelativePath(validating: "Singular.xcframework"))
                                    .pathString
                            ))],
                            customSettings: [
                                "HEADER_SEARCH_PATHS": ["$(inherited)", "$(SRCROOT)/Sources/Singular/include"],
                                "DEFINES_MODULE": "NO",
                                "OTHER_CFLAGS": .array(["$(inherited)", "-fmodule-name=Singular"]),
                                "OTHER_SWIFT_FLAGS": [
                                    "$(inherited)",
                                ],
                                "PRODUCT_MODULE_NAME": "Singular",
                            ],
                            moduleMap: "$(SRCROOT)/Derived/Singular.modulemap"
                        ),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_whenTargetNameContainsSpacesAndDefaultPathUsesUnderscores_mapsTargetSources() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(
            at: basePath.appending(try RelativePath(validating: "Package/Sources/INCITS_4_1986"))
        )

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "INCITS 4 1986", type: .library(.automatic), targets: ["INCITS 4 1986"]),
                    ],
                    targets: [
                        .test(name: "INCITS 4 1986"),
                    ],
                    platforms: [.macos],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )

        let mappedTarget = try #require(project?.targets.first(where: { $0.name == "INCITS_4_1986" }))
        let sources = try #require(mappedTarget.sources)
        #expect(sources.globs == ["\(basePath.pathString)/Package/Sources/INCITS_4_1986/**"])
    }

    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_whenTargetNameContainsSpaces_sanitizesBundleIdentifier() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(
            at: basePath.appending(try RelativePath(validating: "Package/Sources/File_System"))
        )

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "File System", type: .library(.automatic), targets: ["File System"]),
                    ],
                    targets: [
                        .test(name: "File System"),
                    ],
                    platforms: [.macos],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )

        let mappedTarget = try #require(project?.targets.first(where: { $0.name == "File_System" }))
        #expect(mappedTarget.productName == "File_System")
        #expect(mappedTarget.bundleId == "File.System")
    }

    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_whenMacroTargetDependsOnPrebuiltProduct_usesPrebuiltSettings() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let prebuiltPath = basePath.appending(components: ".build", "prebuilts", "swift-syntax")
        let checkoutPath = basePath.appending(components: ".build", "checkouts", "swift-syntax")

        try await fileSystem.makeDirectory(
            at: basePath.appending(try RelativePath(validating: "Package/Sources/MyMacro"))
        )
        try await fileSystem.makeDirectory(
            at: basePath.appending(try RelativePath(validating: "Package/Sources/Library"))
        )

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageType: .external(
                artifactPaths: [:],
                packagePrebuilts: [
                    "swift-syntax": [
                        "SwiftSyntax": SwiftPackageManagerPrebuilt(
                            identity: "swift-syntax",
                            version: "601.0.0",
                            libraryName: "SwiftSyntax",
                            path: prebuiltPath,
                            checkoutPath: checkoutPath,
                            products: ["SwiftSyntax"],
                            includePath: [try RelativePath(validating: "Sources/_SwiftSyntaxCShims/include")],
                            cModules: ["_SwiftSyntaxCShims"]
                        ),
                    ],
                ]
            ),
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Library", type: .library(.automatic), targets: ["Library"]),
                    ],
                    targets: [
                        .test(
                            name: "Library",
                            dependencies: [
                                .target(name: "MyMacro", condition: nil),
                            ]
                        ),
                        .test(
                            name: "MyMacro",
                            type: .macro,
                            dependencies: [
                                .product(
                                    name: "SwiftSyntax",
                                    package: "swift-syntax",
                                    moduleAliases: nil,
                                    condition: nil
                                ),
                            ]
                        ),
                    ],
                    platforms: [.macos]
                ),
            ]
        )

        let target = try #require(project?.targets.first(where: { $0.name == "MyMacro" }))
        #expect(target.dependencies.isEmpty)
        #expect(
            target.settings?.base["OTHER_SWIFT_FLAGS"] == .array([
                "$(inherited)",
                "-I",
                "$(SRCROOT)/../.build/prebuilts/swift-syntax/Modules",
                "-I",
                "$(SRCROOT)/../.build/checkouts/swift-syntax/Sources/_SwiftSyntaxCShims/include",
            ])
        )
        #expect(target.settings?.base["SWIFT_PACKAGE_NAME"] == .string("Package"))
        #expect(
            target.settings?.base["LIBRARY_SEARCH_PATHS"] == .array([
                "$(inherited)",
                "$(SRCROOT)/../.build/prebuilts/swift-syntax/lib",
            ])
        )
        #expect(
            target.settings?.base["LD_RUNPATH_SEARCH_PATHS"] == .array([
                "$(inherited)",
                "$(SRCROOT)/../.build/prebuilts/swift-syntax/lib",
            ])
        )
        #expect(target.settings?.base["OTHER_LDFLAGS"] == .array(["$(inherited)", "-lSwiftSyntax"]))
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider,
        arguments: [
            XcodeGraph.SettingValue.array(["$(inherited)", "-DSTAGING"]),
            XcodeGraph.SettingValue.string("$(inherited) -DSTAGING"),
        ]
    ) func map_targetWithSwiftPMFlags_inheritsPackageBaseSettings(
        baseFlags: XcodeGraph.SettingValue
    ) async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(
            at: basePath.appending(try RelativePath(validating: "Package/Sources/Target"))
        )

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageType: .local,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Target", type: .library(.automatic), targets: ["Target"]),
                    ],
                    targets: [
                        .test(
                            name: "Target",
                            settings: [
                                .init(
                                    tool: .swift,
                                    name: .enableExperimentalFeature,
                                    condition: nil,
                                    value: ["Lifetimes"]
                                ),
                            ]
                        ),
                    ],
                    platforms: [.ios]
                ),
            ],
            packageSettings: .test(
                baseSettings: Settings.default.with(base: [
                    "OTHER_SWIFT_FLAGS": baseFlags,
                ])
            )
        )

        let target = try #require(project?.targets.first(where: { $0.name == "Target" }))
        #expect(
            target.settings?.base["OTHER_SWIFT_FLAGS"] == .array([
                "$(inherited)",
                "-enable-experimental-feature \"Lifetimes\"",
            ])
        )
        #expect(target.settings?.base["SWIFT_PACKAGE_NAME"] == .string("Package"))
        let projectFlags: [String]
        switch project?.settings?.base["OTHER_SWIFT_FLAGS"] {
        case let .array(flags):
            projectFlags = flags
        case let .string(flags):
            projectFlags = flags.split(separator: " ").map(String.init)
        case nil:
            Issue.record("Expected project-level OTHER_SWIFT_FLAGS to be a string or an array")
            return
        @unknown default:
            Issue.record("Expected project-level OTHER_SWIFT_FLAGS to be a string or an array")
            return
        }
        #expect(projectFlags.filter { $0 == "-DSTAGING" }.count == 1)
    }

    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_targetWithSwiftPMFlags_appendsTargetSettingsWithoutInherited() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(
            at: basePath.appending(try RelativePath(validating: "Package/Sources/Target"))
        )

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageType: .local,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Target", type: .library(.automatic), targets: ["Target"]),
                    ],
                    targets: [
                        .test(
                            name: "Target",
                            settings: [
                                .init(
                                    tool: .swift,
                                    name: .enableExperimentalFeature,
                                    condition: nil,
                                    value: ["Lifetimes"]
                                ),
                            ]
                        ),
                    ],
                    platforms: [.ios]
                ),
            ],
            packageSettings: .test(
                baseSettings: .default,
                targetSettings: [
                    "Target": .test(base: ["OTHER_SWIFT_FLAGS": ["-DSTAGING"]]),
                ]
            )
        )

        let target = try #require(project?.targets.first(where: { $0.name == "Target" }))
        #expect(
            target.settings?.base["OTHER_SWIFT_FLAGS"] == .array([
                "$(inherited)",
                "-enable-experimental-feature \"Lifetimes\"",
                "-DSTAGING",
            ])
        )
        #expect(target.settings?.base["SWIFT_PACKAGE_NAME"] == .string("Package"))
    }

    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_macroTarget_appliesBaseSettingsBaseToMacroTarget() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(
            at: basePath.appending(try RelativePath(validating: "Package/Sources/Library"))
        )
        try await fileSystem.makeDirectory(
            at: basePath.appending(try RelativePath(validating: "Package/Sources/MyMacro"))
        )

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageType: .local,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Library", type: .library(.automatic), targets: ["Library"]),
                    ],
                    targets: [
                        .test(
                            name: "Library",
                            dependencies: [.target(name: "MyMacro", condition: nil)]
                        ),
                        .test(name: "MyMacro", type: .macro),
                    ],
                    platforms: [.init(platformName: "macos", version: "11.0", options: [])]
                ),
            ],
            packageSettings: .test(
                baseSettings: Settings.default.with(base: ["MACOSX_DEPLOYMENT_TARGET": "15.0"])
            )
        )

        let macroTarget = try #require(project?.targets.first(where: { $0.name == "MyMacro" }))
        #expect(macroTarget.settings?.base["MACOSX_DEPLOYMENT_TARGET"] == .string("15.0"))
    }

    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_regularTarget_doesNotApplyBaseSettingsBundleIdentifierToTarget() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await fileSystem.makeDirectory(
            at: basePath.appending(try RelativePath(validating: "Package/Sources/_RopeModule"))
        )

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageType: .local,
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "_RopeModule", type: .library(.automatic), targets: ["_RopeModule"]),
                    ],
                    targets: [
                        .test(name: "_RopeModule"),
                    ],
                    platforms: [.ios]
                ),
            ],
            packageSettings: .test(
                baseSettings: Settings.default.with(base: [
                    "PRODUCT_BUNDLE_IDENTIFIER": "com.example.$(PRODUCT_NAME)",
                    "EXCLUDED_ARCHS[sdk=iphonesimulator*]": "x86_64",
                ])
            )
        )

        let target = try #require(project?.targets.first(where: { $0.name == "_RopeModule" }))
        #expect(target.bundleId == "-RopeModule")
        #expect(target.settings?.base["PRODUCT_BUNDLE_IDENTIFIER"] == nil)
        #expect(target.settings?.base["EXCLUDED_ARCHS[sdk=iphonesimulator*]"] == .string("x86_64"))
    }

    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_whenRegularTargetDependsOnPrebuiltProduct_keepsSourceDependency() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)

        try await fileSystem.makeDirectory(
            at: basePath.appending(try RelativePath(validating: "Package/Sources/Library"))
        )

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageType: .external(
                artifactPaths: [:],
                packagePrebuilts: [
                    "swift-syntax": [
                        "SwiftSyntax": SwiftPackageManagerPrebuilt(
                            identity: "swift-syntax",
                            version: "601.0.0",
                            libraryName: "SwiftSyntax",
                            path: basePath.appending(components: ".build", "prebuilts", "swift-syntax"),
                            checkoutPath: nil,
                            products: ["SwiftSyntax"],
                            includePath: nil,
                            cModules: ["_SwiftSyntaxCShims"]
                        ),
                    ],
                ]
            ),
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Library", type: .library(.automatic), targets: ["Library"]),
                    ],
                    targets: [
                        .test(
                            name: "Library",
                            dependencies: [
                                .product(
                                    name: "SwiftSyntax",
                                    package: "swift-syntax",
                                    moduleAliases: nil,
                                    condition: nil
                                ),
                            ]
                        ),
                    ],
                    platforms: [.ios]
                ),
            ]
        )

        let target = try #require(project?.targets.first)
        #expect(target.dependencies == [.external(name: "SwiftSyntax", condition: nil)])
        #expect(
            target.settings?.base["OTHER_SWIFT_FLAGS"] == .array([
                "$(inherited)",
            ])
        )
        #expect(target.settings?.base["SWIFT_PACKAGE_NAME"] == .string("Package"))
        #expect(target.settings?.base["LIBRARY_SEARCH_PATHS"] == nil)
        #expect(target.settings?.base["OTHER_LDFLAGS"] == nil)
    }

    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_whenLocalMacroTargetDependsOnPrebuiltProduct_usesPrebuiltSettings() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let prebuiltPath = basePath.appending(components: ".build", "prebuilts", "swift-syntax")

        try await fileSystem.makeDirectory(
            at: basePath.appending(try RelativePath(validating: "Package/Sources/MyMacro"))
        )

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageType: .external(
                origin: .local,
                artifactPaths: [:],
                packagePrebuilts: [
                    "swift-syntax": [
                        "SwiftSyntax": SwiftPackageManagerPrebuilt(
                            identity: "swift-syntax",
                            version: "601.0.0",
                            libraryName: "SwiftSyntax",
                            path: prebuiltPath,
                            checkoutPath: nil,
                            products: ["SwiftSyntax"],
                            includePath: nil,
                            cModules: ["_SwiftSyntaxCShims"]
                        ),
                    ],
                ]
            ),
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [],
                    targets: [
                        .test(
                            name: "MyMacro",
                            type: .macro,
                            dependencies: [
                                .product(
                                    name: "SwiftSyntax",
                                    package: "swift-syntax",
                                    moduleAliases: nil,
                                    condition: nil
                                ),
                            ]
                        ),
                    ],
                    platforms: [.macos]
                ),
            ]
        )

        let target = try #require(project?.targets.first(where: { $0.name == "MyMacro" }))
        #expect(target.dependencies.isEmpty)
        #expect(
            target.settings?.base["OTHER_SWIFT_FLAGS"] == .array([
                "$(inherited)",
                "-I",
                "$(SRCROOT)/../.build/prebuilts/swift-syntax/Modules",
                "-I",
                "$(SRCROOT)/../.build/prebuilts/swift-syntax/include/_SwiftSyntaxCShims",
            ])
        )
        #expect(target.settings?.base["SWIFT_PACKAGE_NAME"] == .string("Package"))
        #expect(
            target.settings?.base["LIBRARY_SEARCH_PATHS"] == .array([
                "$(inherited)",
                "$(SRCROOT)/../.build/prebuilts/swift-syntax/lib",
            ])
        )
        #expect(
            target.settings?.base["LD_RUNPATH_SEARCH_PATHS"] == .array([
                "$(inherited)",
                "$(SRCROOT)/../.build/prebuilts/swift-syntax/lib",
            ])
        )
        #expect(target.settings?.base["OTHER_LDFLAGS"] == .array(["$(inherited)", "-lSwiftSyntax"]))
    }

    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_whenRemoteMacroPackageHasTestTargetReachingMacroThroughLibrary_usesPrebuiltSettings() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await makeMacroPackageDirectories(basePath: basePath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageType: swiftSyntaxPrebuiltPackageType(origin: .remote, basePath: basePath),
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Library", type: .library(.automatic), targets: ["Library"]),
                    ],
                    targets: [
                        .test(name: "Library", dependencies: [.target(name: "MyMacro", condition: nil)]),
                        .test(name: "MyMacro", type: .macro, dependencies: [swiftSyntaxProductDependency]),
                        .test(
                            name: "LibraryTests",
                            type: .test,
                            dependencies: [.target(name: "Library", condition: nil)]
                        ),
                    ],
                    platforms: [.macos]
                ),
            ]
        )

        let target = try #require(project?.targets.first(where: { $0.name == "MyMacro" }))
        #expect(target.dependencies.isEmpty)
        #expect(target.settings?.base["OTHER_LDFLAGS"] == .array(["$(inherited)", "-lSwiftSyntax"]))
    }

    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_whenGeneratedTestTargetReachesMacroThroughLibrary_usesPrebuiltSettings() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await makeMacroPackageDirectories(basePath: basePath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageType: swiftSyntaxPrebuiltPackageType(origin: .local, basePath: basePath),
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Library", type: .library(.automatic), targets: ["Library"]),
                    ],
                    targets: [
                        .test(name: "Library", dependencies: [.target(name: "MyMacro", condition: nil)]),
                        .test(name: "MyMacro", type: .macro, dependencies: [swiftSyntaxProductDependency]),
                        .test(
                            name: "LibraryTests",
                            type: .test,
                            dependencies: [.target(name: "Library", condition: nil)]
                        ),
                    ],
                    platforms: [.macos]
                ),
            ],
            packageSettings: .test(includeLocalPackageTestTargets: true)
        )

        let macroTarget = try #require(project?.targets.first(where: { $0.name == "MyMacro" }))
        #expect(macroTarget.dependencies.isEmpty)
        #expect(macroTarget.settings?.base["OTHER_LDFLAGS"] == .array(["$(inherited)", "-lSwiftSyntax"]))
        #expect(project?.targets.contains(where: { $0.name == "LibraryTests" }) == true)
    }

    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_whenGeneratedMacroTestTargetDependsOnPrebuiltProduct_usesPrebuiltSettings() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await makeMacroPackageDirectories(basePath: basePath)

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageType: swiftSyntaxPrebuiltPackageType(origin: .local, basePath: basePath),
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Library", type: .library(.automatic), targets: ["Library"]),
                    ],
                    targets: [
                        .test(name: "Library", dependencies: [.target(name: "MyMacro", condition: nil)]),
                        .test(name: "MyMacro", type: .macro, dependencies: [swiftSyntaxProductDependency]),
                        .test(
                            name: "MyMacroTests",
                            type: .test,
                            dependencies: [.target(name: "MyMacro", condition: nil), swiftSyntaxProductDependency]
                        ),
                    ],
                    platforms: [.macos]
                ),
            ],
            packageSettings: .test(includeLocalPackageTestTargets: true)
        )

        let testTarget = try #require(project?.targets.first(where: { $0.name == "MyMacroTests" }))
        #expect(!testTarget.dependencies.contains(.external(name: "SwiftSyntax", condition: nil)))
        #expect(testTarget.settings?.base["OTHER_LDFLAGS"] == .array(["$(inherited)", "-lSwiftSyntax"]))
    }

    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_whenTargetSharedByMacroAndLibraryDependsOnPrebuiltProduct_keepsSourceDependencies() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await makeMacroPackageDirectories(basePath: basePath)
        try await fileSystem.makeDirectory(
            at: basePath.appending(try RelativePath(validating: "Package/Sources/Shared"))
        )

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageType: swiftSyntaxPrebuiltPackageType(origin: .remote, basePath: basePath),
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Library", type: .library(.automatic), targets: ["Library"]),
                    ],
                    targets: [
                        .test(
                            name: "Library",
                            dependencies: [
                                .target(name: "MyMacro", condition: nil),
                                .target(name: "Shared", condition: nil),
                            ]
                        ),
                        .test(
                            name: "MyMacro",
                            type: .macro,
                            dependencies: [.target(name: "Shared", condition: nil), swiftSyntaxProductDependency]
                        ),
                        .test(name: "Shared", dependencies: [swiftSyntaxProductDependency]),
                    ],
                    platforms: [.macos]
                ),
            ]
        )

        // `Library` builds `Shared` into apps on every platform, macOS included, where `Library` and the apps would also need
        // the prebuilt's module search paths and library, so the package keeps its source dependencies.
        let macroTarget = try #require(project?.targets.first(where: { $0.name == "MyMacro" }))
        #expect(macroTarget.dependencies.contains(.external(name: "SwiftSyntax", condition: nil)))
        #expect(macroTarget.settings?.base["OTHER_LDFLAGS"] == nil)
        let sharedTarget = try #require(project?.targets.first(where: { $0.name == "Shared" }))
        #expect(sharedTarget.dependencies == [.external(name: "SwiftSyntax", condition: nil)])
        #expect(sharedTarget.settings?.base["OTHER_LDFLAGS"] == nil)
    }

    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_whenMacroOnlyReachesPrebuiltProductThroughSupportTarget_linksThePrebuilt() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await makeMacroPackageDirectories(basePath: basePath)
        try await fileSystem.makeDirectory(
            at: basePath.appending(try RelativePath(validating: "Package/Sources/MacrosSupport"))
        )

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageType: swiftSyntaxPrebuiltPackageType(origin: .remote, basePath: basePath),
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Library", type: .library(.automatic), targets: ["Library"]),
                        .init(name: "MacrosSupport", type: .library(.automatic), targets: ["MacrosSupport"]),
                    ],
                    targets: [
                        .test(name: "Library", dependencies: [.target(name: "MyMacro", condition: nil)]),
                        .test(name: "MyMacro", type: .macro, dependencies: [.target(name: "MacrosSupport", condition: nil)]),
                        .test(name: "MacrosSupport", dependencies: [swiftSyntaxProductDependency]),
                    ],
                    platforms: [.ios, .macos]
                ),
            ]
        )

        // The macro imports `MacrosSupport`, whose module imports swift-syntax, and links it statically, so it needs the
        // prebuilt's module search paths and library even though it doesn't depend on swift-syntax itself.
        let macroTarget = try #require(project?.targets.first(where: { $0.name == "MyMacro" }))
        #expect(macroTarget.dependencies == [.target(name: "MacrosSupport", condition: nil)])
        #expect(macroTarget.settings?.base["OTHER_LDFLAGS"] == .array(["$(inherited)", "-lSwiftSyntax"]))
        #expect(macroTarget.settings?.base["LIBRARY_SEARCH_PATHS"] == .array([
            "$(inherited)",
            "$(SRCROOT)/../.build/prebuilts/swift-syntax/lib",
        ]))
        let supportTarget = try #require(project?.targets.first(where: { $0.name == "MacrosSupport" }))
        expectMacOSOnlySwiftSyntaxPrebuiltSettings(supportTarget)
    }

    /// Mirrors swift-case-paths' `CasePathsMacrosSupport`: a library product that depends on swift-syntax and that macros
    /// consume. https://github.com/tuist/tuist/issues/15703
    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_whenMacroSupportLibraryProductDependsOnPrebuiltProduct_usesPrebuiltOnlyOnMacOS() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await makeMacroPackageDirectories(basePath: basePath)
        try await fileSystem.makeDirectory(
            at: basePath.appending(try RelativePath(validating: "Package/Sources/MacrosSupport"))
        )

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageType: swiftSyntaxPrebuiltPackageType(origin: .remote, basePath: basePath),
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Library", type: .library(.automatic), targets: ["Library"]),
                        .init(name: "MacrosSupport", type: .library(.automatic), targets: ["MacrosSupport"]),
                    ],
                    targets: [
                        .test(name: "Library", dependencies: [.target(name: "MyMacro", condition: nil)]),
                        .test(
                            name: "MyMacro",
                            type: .macro,
                            dependencies: [.target(name: "MacrosSupport", condition: nil), swiftSyntaxProductDependency]
                        ),
                        .test(name: "MacrosSupport", dependencies: [swiftSyntaxProductDependency]),
                    ],
                    platforms: [.ios, .macos]
                ),
            ]
        )

        let macroTarget = try #require(project?.targets.first(where: { $0.name == "MyMacro" }))
        #expect(macroTarget.dependencies == [.target(name: "MacrosSupport", condition: nil)])
        #expect(macroTarget.settings?.base["OTHER_LDFLAGS"] == .array(["$(inherited)", "-lSwiftSyntax"]))
        let supportTarget = try #require(project?.targets.first(where: { $0.name == "MacrosSupport" }))
        #expect(supportTarget.dependencies == [.external(name: "SwiftSyntax", condition: nonMacOSPlatformCondition)])
        expectMacOSOnlySwiftSyntaxPrebuiltSettings(supportTarget)
    }

    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_whenMacroReachedTargetHasPlatformConditionedPrebuiltProducts_keepsSourceOnlyOnOtherPlatforms() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await makeMacroPackageDirectories(basePath: basePath)
        try await fileSystem.makeDirectory(
            at: basePath.appending(try RelativePath(validating: "Package/Sources/MacrosSupport"))
        )
        let swiftSyntaxPrebuilt = SwiftPackageManagerPrebuilt(
            identity: "swift-syntax",
            version: "601.0.0",
            libraryName: "SwiftSyntax",
            path: basePath.appending(components: ".build", "prebuilts", "swift-syntax"),
            checkoutPath: nil,
            products: ["SwiftSyntax", "SwiftParser"],
            includePath: nil,
            cModules: ["_SwiftSyntaxCShims"]
        )

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageType: .external(
                artifactPaths: [:],
                packagePrebuilts: ["swift-syntax": ["SwiftSyntax": swiftSyntaxPrebuilt, "SwiftParser": swiftSyntaxPrebuilt]]
            ),
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "MacrosSupport", type: .library(.automatic), targets: ["MacrosSupport"]),
                    ],
                    targets: [
                        .test(name: "MyMacro", type: .macro, dependencies: [.target(name: "MacrosSupport", condition: nil)]),
                        .test(
                            name: "MacrosSupport",
                            dependencies: [
                                .product(
                                    name: "SwiftSyntax",
                                    package: "swift-syntax",
                                    moduleAliases: nil,
                                    condition: .init(platformNames: ["ios", "macos"], config: nil)
                                ),
                                .product(
                                    name: "SwiftParser",
                                    package: "swift-syntax",
                                    moduleAliases: nil,
                                    condition: .init(platformNames: ["macos"], config: nil)
                                ),
                            ]
                        ),
                    ],
                    platforms: [.ios, .macos]
                ),
            ]
        )

        let supportTarget = try #require(project?.targets.first(where: { $0.name == "MacrosSupport" }))
        #expect(supportTarget.dependencies == [.external(name: "SwiftSyntax", condition: .when([.ios]))])
        expectMacOSOnlySwiftSyntaxPrebuiltSettings(supportTarget)
    }

    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_whenMacroOnlyReachesPrebuiltProductThroughSupportChain_usesPrebuiltOnlyOnMacOSForTheChain() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await makeMacroPackageDirectories(basePath: basePath, targets: ["SupportA", "SupportB"])

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageType: swiftSyntaxPrebuiltPackageType(origin: .remote, basePath: basePath),
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Library", type: .library(.automatic), targets: ["Library"]),
                        .init(name: "SupportA", type: .library(.automatic), targets: ["SupportA"]),
                    ],
                    targets: [
                        .test(name: "Library", dependencies: [.target(name: "MyMacro", condition: nil)]),
                        .test(name: "MyMacro", type: .macro, dependencies: [.target(name: "SupportA", condition: nil)]),
                        .test(name: "SupportA", dependencies: [.target(name: "SupportB", condition: nil)]),
                        .test(name: "SupportB", dependencies: [swiftSyntaxProductDependency]),
                    ],
                    platforms: [.ios, .macos]
                ),
            ]
        )

        let macroTarget = try #require(project?.targets.first(where: { $0.name == "MyMacro" }))
        #expect(macroTarget.settings?.base["OTHER_LDFLAGS"] == .array(["$(inherited)", "-lSwiftSyntax"]))
        let supportA = try #require(project?.targets.first(where: { $0.name == "SupportA" }))
        #expect(supportA.dependencies == [.target(name: "SupportB", condition: nil)])
        expectMacOSOnlySwiftSyntaxPrebuiltSettings(supportA)
        let supportB = try #require(project?.targets.first(where: { $0.name == "SupportB" }))
        #expect(supportB.dependencies == [.external(name: "SwiftSyntax", condition: nonMacOSPlatformCondition)])
        expectMacOSOnlySwiftSyntaxPrebuiltSettings(supportB)
        let library = try #require(project?.targets.first(where: { $0.name == "Library" }))
        expectNoSwiftSyntaxPrebuiltSettings(library)
    }

    /// A macro test that also tests a library using swift-syntax links that library, which apps build from source, so the
    /// test can't link the prebuilt as well.
    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_whenMacroTestAlsoDependsOnLibraryUsingPrebuiltProduct_keepsSourceDependencies() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await makeMacroPackageDirectories(basePath: basePath, targets: ["Lint", "LintMacros"], testTargets: ["LintTests"])

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageType: swiftSyntaxPrebuiltPackageType(origin: .local, basePath: basePath),
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Lint", type: .library(.automatic), targets: ["Lint"]),
                    ],
                    targets: [
                        .test(name: "Lint", dependencies: [swiftSyntaxProductDependency]),
                        .test(name: "LintMacros", type: .macro, dependencies: [swiftSyntaxProductDependency]),
                        .test(
                            name: "LintTests",
                            type: .test,
                            dependencies: [
                                .target(name: "Lint", condition: nil),
                                .target(name: "LintMacros", condition: nil),
                            ]
                        ),
                    ],
                    platforms: [.ios, .macos]
                ),
            ],
            packageSettings: .test(includeLocalPackageTestTargets: true)
        )

        let lint = try #require(project?.targets.first(where: { $0.name == "Lint" }))
        #expect(lint.dependencies == [.external(name: "SwiftSyntax", condition: nil)])
        expectNoSwiftSyntaxPrebuiltSettings(lint)
        let macroTarget = try #require(project?.targets.first(where: { $0.name == "LintMacros" }))
        #expect(macroTarget.dependencies == [.external(name: "SwiftSyntax", condition: nil)])
        expectNoSwiftSyntaxPrebuiltSettings(macroTarget)
        let testTarget = try #require(project?.targets.first(where: { $0.name == "LintTests" }))
        expectNoSwiftSyntaxPrebuiltSettings(testTarget)
    }

    /// Targets that use a macro don't link it, so a library that a test reaches on its way to a macro doesn't link the
    /// macro's prebuilts.
    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_whenTestReachesMacroThroughLibrary_doesNotLinkPrebuiltIntoLibrary() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        try await makeMacroPackageDirectories(
            basePath: basePath,
            targets: ["Feature", "FeatureMacros"],
            testTargets: ["FeatureTests"]
        )

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageType: swiftSyntaxPrebuiltPackageType(origin: .local, basePath: basePath),
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [
                        .init(name: "Feature", type: .library(.automatic), targets: ["Feature"]),
                    ],
                    targets: [
                        .test(name: "Feature", dependencies: [.target(name: "FeatureMacros", condition: nil)]),
                        .test(name: "FeatureMacros", type: .macro, dependencies: [swiftSyntaxProductDependency]),
                        .test(
                            name: "FeatureTests",
                            type: .test,
                            dependencies: [.target(name: "Feature", condition: nil)]
                        ),
                    ],
                    platforms: [.ios, .macos]
                ),
            ],
            packageSettings: .test(includeLocalPackageTestTargets: true)
        )

        let macroTarget = try #require(project?.targets.first(where: { $0.name == "FeatureMacros" }))
        #expect(macroTarget.dependencies.isEmpty)
        #expect(macroTarget.settings?.base["OTHER_LDFLAGS"] == .array(["$(inherited)", "-lSwiftSyntax"]))
        let feature = try #require(project?.targets.first(where: { $0.name == "Feature" }))
        #expect(feature.dependencies == [.target(name: "FeatureMacros", condition: nil)])
        expectNoSwiftSyntaxPrebuiltSettings(feature)
        let testTarget = try #require(project?.targets.first(where: { $0.name == "FeatureTests" }))
        expectNoSwiftSyntaxPrebuiltSettings(testTarget)
    }

    /// Macros in other packages import and link the macro support libraries that swift-case-paths' and other packages'
    /// products vend, which link the prebuilt on macOS, so they need the prebuilt even when they don't depend on
    /// swift-syntax themselves.
    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_whenMacrosConsumeMacroSupportProductsOfOtherPackages_linkThePrebuilt() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let packageInfos: [String: PackageInfo] = [
            // Packages are named so that the consumer comes first, before the packages whose products it consumes.
            "a-macros": .test(
                name: "a-macros",
                products: [.init(name: "AMacrosLibrary", type: .library(.automatic), targets: ["AMacrosLibrary"])],
                targets: [
                    .test(name: "AMacrosLibrary", dependencies: [.target(name: "AMacros", condition: nil)]),
                    .test(
                        name: "AMacros",
                        type: .macro,
                        dependencies: [
                            .product(name: "MacrosKit", package: "b-macros-kit", moduleAliases: nil, condition: nil),
                        ]
                    ),
                ],
                platforms: [.ios, .macos]
            ),
            "b-macros-kit": .test(
                name: "b-macros-kit",
                products: [.init(name: "MacrosKit", type: .library(.automatic), targets: ["MacrosKit"])],
                targets: [
                    .test(name: "KitMacros", type: .macro, dependencies: [.target(name: "MacrosKit", condition: nil)]),
                    .test(
                        name: "MacrosKit",
                        dependencies: [
                            .product(name: "CasePathsMacrosSupport", package: "c-case-paths", moduleAliases: nil, condition: nil),
                        ]
                    ),
                ],
                platforms: [.ios, .macos]
            ),
            "c-case-paths": casePathsPackageInfo(name: "c-case-paths"),
        ]
        try await makePackageDirectories(basePath: basePath, packageInfos: packageInfos)

        let projects = try await mapPackages(basePath: basePath, packageInfos: packageInfos)

        let consumerMacro = try #require(projects["a-macros"]?.targets.first(where: { $0.name == "AMacros" }))
        #expect(consumerMacro.settings?.base["OTHER_LDFLAGS"] == .array(["$(inherited)", "-lSwiftSyntax"]))
        #expect(consumerMacro.settings?.base["OTHER_SWIFT_FLAGS"] == .array([
            "$(inherited)",
            "-I", "$(SRCROOT)/../.build/prebuilts/swift-syntax/Modules",
            "-I", "$(SRCROOT)/../.build/prebuilts/swift-syntax/include/_SwiftSyntaxCShims",
        ]))
        let consumerLibrary = try #require(projects["a-macros"]?.targets.first(where: { $0.name == "AMacrosLibrary" }))
        expectNoSwiftSyntaxPrebuiltSettings(consumerLibrary)
        let macrosKit = try #require(projects["b-macros-kit"]?.targets.first(where: { $0.name == "MacrosKit" }))
        #expect(macrosKit.dependencies == [.external(name: "CasePathsMacrosSupport", condition: nil)])
        expectMacOSOnlySwiftSyntaxPrebuiltSettings(macrosKit)
        let support = try #require(projects["c-case-paths"]?.targets.first(where: { $0.name == "CasePathsMacrosSupport" }))
        expectMacOSOnlySwiftSyntaxPrebuiltSettings(support)
    }

    /// A target that apps build, macOS apps included, can't import a product that links the prebuilt on macOS, so the
    /// package that vends it keeps its source products, as it did before such products linked the prebuilt.
    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_whenLibraryOfAnotherPackageConsumesMacroSupportProduct_keepsSourceDependencies() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let packageInfos: [String: PackageInfo] = [
            "a-codegen": .test(
                name: "a-codegen",
                products: [.init(name: "Codegen", type: .library(.automatic), targets: ["Codegen"])],
                targets: [
                    .test(
                        name: "Codegen",
                        dependencies: [
                            .product(name: "CasePathsMacrosSupport", package: "c-case-paths", moduleAliases: nil, condition: nil),
                        ]
                    ),
                ],
                platforms: [.ios, .macos]
            ),
            "c-case-paths": casePathsPackageInfo(name: "c-case-paths"),
        ]
        try await makePackageDirectories(basePath: basePath, packageInfos: packageInfos)

        let projects = try await mapPackages(basePath: basePath, packageInfos: packageInfos)

        let codegen = try #require(projects["a-codegen"]?.targets.first(where: { $0.name == "Codegen" }))
        expectNoSwiftSyntaxPrebuiltSettings(codegen)
        let support = try #require(projects["c-case-paths"]?.targets.first(where: { $0.name == "CasePathsMacrosSupport" }))
        #expect(support.dependencies == [.external(name: "SwiftSyntax", condition: nil)])
        expectNoSwiftSyntaxPrebuiltSettings(support)
        let macro = try #require(projects["c-case-paths"]?.targets.first(where: { $0.name == "CasePathsMacros" }))
        #expect(macro.dependencies.contains(.external(name: "SwiftSyntax", condition: nil)))
        expectNoSwiftSyntaxPrebuiltSettings(macro)
    }

    /// A test that links a library apps build, as well as a target only macros reach, builds for the apps' platforms, where
    /// it can't link the macOS-only prebuilt. Like SwiftPM, which only treats tests of macros as host-only, the package
    /// keeps its source products.
    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_whenLocalPackageTestLinksAppLibraryAndMacroOnlyTarget_keepsSourceDependencies() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let packageInfos = [
            "case-paths": casePathsPackageInfo(name: "case-paths", testTargets: [
                .test(
                    name: "CasePathsTests",
                    type: .test,
                    dependencies: [
                        .target(name: "CasePaths", condition: nil),
                        .target(name: "CasePathsMacrosSupport", condition: nil),
                    ]
                ),
            ]),
        ]
        try await makePackageDirectories(basePath: basePath, packageInfos: packageInfos)

        let project = try await subject.map(
            package: "case-paths",
            basePath: basePath,
            packageType: swiftSyntaxPrebuiltPackageType(origin: .local, basePath: basePath),
            packageInfos: packageInfos,
            packageSettings: .test(includeLocalPackageTestTargets: true)
        )

        let testTarget = try #require(project?.targets.first(where: { $0.name == "CasePathsTests" }))
        expectNoSwiftSyntaxPrebuiltSettings(testTarget)
        let support = try #require(project?.targets.first(where: { $0.name == "CasePathsMacrosSupport" }))
        #expect(support.dependencies == [.external(name: "SwiftSyntax", condition: nil)])
        expectNoSwiftSyntaxPrebuiltSettings(support)
        let macro = try #require(project?.targets.first(where: { $0.name == "CasePathsMacros" }))
        #expect(macro.dependencies.contains(.external(name: "SwiftSyntax", condition: nil)))
        expectNoSwiftSyntaxPrebuiltSettings(macro)
    }

    /// The planner doesn't see the targets of the workspace's projects. One that depends on a product that links the
    /// prebuilt on macOS, such as a macOS tool importing `CasePathsMacrosSupport`, would get neither its search paths nor
    /// its library, so the package that vends it keeps its source products. Other products leave it unchanged.
    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider,
        arguments: [("CasePathsMacrosSupport", true), ("CasePaths", false)]
    ) func map_whenProjectsDependOnProducts_keepSourceDependenciesOnlyForProductsLinkingThePrebuilt(
        externalDependencyName: String,
        keepsSourceDependencies: Bool
    ) async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let packageInfos = ["c-case-paths": casePathsPackageInfo(name: "c-case-paths")]
        try await makePackageDirectories(basePath: basePath, packageInfos: packageInfos)

        let projects = try await mapPackages(
            basePath: basePath,
            packageInfos: packageInfos,
            externalDependencyNames: [externalDependencyName]
        )

        let support = try #require(projects["c-case-paths"]?.targets.first(where: { $0.name == "CasePathsMacrosSupport" }))
        let macro = try #require(projects["c-case-paths"]?.targets.first(where: { $0.name == "CasePathsMacros" }))
        if keepsSourceDependencies {
            #expect(support.dependencies == [.external(name: "SwiftSyntax", condition: nil)])
            expectNoSwiftSyntaxPrebuiltSettings(support)
            expectNoSwiftSyntaxPrebuiltSettings(macro)
        } else {
            expectMacOSOnlySwiftSyntaxPrebuiltSettings(support)
            #expect(macro.settings?.base["OTHER_LDFLAGS"] == .array(["$(inherited)", "-lSwiftSyntax"]))
        }
    }

    /// A target only macros reach that links another package's product, here reaching swift-syntax through a third
    /// package. When only macros reach those packages, they link the prebuilt on macOS like swift-build. When the
    /// workspace's projects link the third package's product, it keeps source swift-syntax, so the second package's
    /// product is built against source swift-syntax too, and the macro, which can't link both, keeps its source products.
    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider,
        arguments: [[], ["CSyntax"]] as [Set<String>]
    ) func map_whenMacroOnlyTargetConsumesProductOfPackageWithoutMacros_linksThePrebuiltUnlessProjectsLinkIt(
        externalDependencyNames: Set<String>
    ) async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let packageInfos: [String: PackageInfo] = [
            "a-macros": .test(
                name: "a-macros",
                products: [.init(name: "AMacrosLibrary", type: .library(.automatic), targets: ["AMacrosLibrary"])],
                targets: [
                    .test(name: "AMacrosLibrary", dependencies: [.target(name: "AMacros", condition: nil)]),
                    .test(
                        name: "AMacros",
                        type: .macro,
                        dependencies: [.target(name: "AMacrosSupport", condition: nil), swiftSyntaxProductDependency]
                    ),
                    .test(
                        name: "AMacrosSupport",
                        dependencies: [
                            swiftSyntaxProductDependency,
                            .product(name: "BKit", package: "b-kit", moduleAliases: nil, condition: nil),
                        ]
                    ),
                ],
                platforms: [.ios, .macos]
            ),
            // Has no macros, and only reaches swift-syntax through `c-syntax`.
            "b-kit": .test(
                name: "b-kit",
                products: [.init(name: "BKit", type: .library(.automatic), targets: ["BKit"])],
                targets: [
                    .test(
                        name: "BKit",
                        dependencies: [.product(name: "CSyntax", package: "c-syntax", moduleAliases: nil, condition: nil)]
                    ),
                ],
                platforms: [.ios, .macos]
            ),
            "c-syntax": .test(
                name: "c-syntax",
                products: [.init(name: "CSyntax", type: .library(.automatic), targets: ["CSyntax"])],
                targets: [.test(name: "CSyntax", dependencies: [swiftSyntaxProductDependency])],
                platforms: [.ios, .macos]
            ),
        ]
        try await makePackageDirectories(basePath: basePath, packageInfos: packageInfos)

        let projects = try await mapPackages(
            basePath: basePath,
            packageInfos: packageInfos,
            externalDependencyNames: externalDependencyNames
        )

        let macro = try target("AMacros", in: "a-macros", of: projects)
        let support = try target("AMacrosSupport", in: "a-macros", of: projects)
        let bKit = try target("BKit", in: "b-kit", of: projects)
        let cSyntax = try target("CSyntax", in: "c-syntax", of: projects)
        if externalDependencyNames.isEmpty {
            #expect(macro.settings?.base["OTHER_LDFLAGS"] == .array(["$(inherited)", "-lSwiftSyntax"]))
            #expect(!macro.dependencies.contains(.external(name: "SwiftSyntax", condition: nil)))
            #expect(support.dependencies == [
                .external(name: "SwiftSyntax", condition: nonMacOSPlatformCondition),
                .external(name: "BKit", condition: nil),
            ])
            expectMacOSOnlySwiftSyntaxPrebuiltSettings(support)
            #expect(bKit.dependencies == [.external(name: "CSyntax", condition: nil)])
            expectMacOSOnlySwiftSyntaxPrebuiltSettings(bKit)
            #expect(cSyntax.dependencies == [.external(name: "SwiftSyntax", condition: nonMacOSPlatformCondition)])
            expectMacOSOnlySwiftSyntaxPrebuiltSettings(cSyntax)
        } else {
            #expect(macro.dependencies.contains(.external(name: "SwiftSyntax", condition: nil)))
            #expect(support.dependencies == [
                .external(name: "SwiftSyntax", condition: nil),
                .external(name: "BKit", condition: nil),
            ])
            #expect(cSyntax.dependencies == [.external(name: "SwiftSyntax", condition: nil)])
            for target in [macro, support, bKit, cSyntax] {
                expectNoSwiftSyntaxPrebuiltSettings(target)
            }
        }
    }

    /// A macro links the targets it shares with app libraries too, so one that links another package's product built
    /// against source swift-syntax can't link the prebuilt alongside it.
    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_whenTargetSharedByMacroAndLibraryConsumesProductUsingSourceSwiftSyntax_keepsSourceDependencies(
    ) async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let packageInfos: [String: PackageInfo] = [
            "a-macros": .test(
                name: "a-macros",
                products: [.init(name: "ALib", type: .library(.automatic), targets: ["ALib"])],
                targets: [
                    .test(
                        name: "ALib",
                        dependencies: [.target(name: "AMacros", condition: nil), .target(name: "Core", condition: nil)]
                    ),
                    .test(
                        name: "AMacros",
                        type: .macro,
                        dependencies: [.target(name: "Core", condition: nil), swiftSyntaxProductDependency]
                    ),
                    .test(
                        name: "Core",
                        dependencies: [.product(name: "BKit", package: "b-kit", moduleAliases: nil, condition: nil)]
                    ),
                ],
                platforms: [.ios, .macos]
            ),
            "b-kit": .test(
                name: "b-kit",
                products: [.init(name: "BKit", type: .library(.automatic), targets: ["BKit"])],
                targets: [.test(name: "BKit", dependencies: [swiftSyntaxProductDependency])],
                platforms: [.ios, .macos]
            ),
        ]
        try await makePackageDirectories(basePath: basePath, packageInfos: packageInfos)

        let projects = try await mapPackages(basePath: basePath, packageInfos: packageInfos)

        let macro = try #require(projects["a-macros"]?.targets.first(where: { $0.name == "AMacros" }))
        #expect(macro.dependencies.contains(.external(name: "SwiftSyntax", condition: nil)))
        expectNoSwiftSyntaxPrebuiltSettings(macro)
    }

    /// An app library sends swift-case-paths back to source products, so a macro of another package that links
    /// `CasePathsMacrosSupport` links source swift-syntax through it and keeps its source products too.
    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_whenAppSendsMacroSupportProviderToSource_macrosConsumingItKeepSourceDependencies() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let packageInfos: [String: PackageInfo] = [
            "a-macros": .test(
                name: "a-macros",
                products: [.init(name: "AMacrosLibrary", type: .library(.automatic), targets: ["AMacrosLibrary"])],
                targets: [
                    .test(name: "AMacrosLibrary", dependencies: [.target(name: "AMacros", condition: nil)]),
                    .test(
                        name: "AMacros",
                        type: .macro,
                        dependencies: [
                            swiftSyntaxProductDependency,
                            .product(name: "CasePathsMacrosSupport", package: "c-case-paths", moduleAliases: nil, condition: nil),
                        ]
                    ),
                ],
                platforms: [.ios, .macos]
            ),
            "b-codegen": .test(
                name: "b-codegen",
                products: [.init(name: "Codegen", type: .library(.automatic), targets: ["Codegen"])],
                targets: [
                    .test(
                        name: "Codegen",
                        dependencies: [
                            .product(name: "CasePathsMacrosSupport", package: "c-case-paths", moduleAliases: nil, condition: nil),
                        ]
                    ),
                ],
                platforms: [.ios, .macos]
            ),
            "c-case-paths": casePathsPackageInfo(name: "c-case-paths"),
        ]
        try await makePackageDirectories(basePath: basePath, packageInfos: packageInfos)

        let projects = try await mapPackages(basePath: basePath, packageInfos: packageInfos)

        let support = try #require(projects["c-case-paths"]?.targets.first(where: { $0.name == "CasePathsMacrosSupport" }))
        expectNoSwiftSyntaxPrebuiltSettings(support)
        let macro = try #require(projects["a-macros"]?.targets.first(where: { $0.name == "AMacros" }))
        #expect(macro.dependencies.contains(.external(name: "SwiftSyntax", condition: nil)))
        expectNoSwiftSyntaxPrebuiltSettings(macro)
    }

    // MARK: - Real package graphs

    //
    // These transcribe the swift-syntax-related parts of real manifests (swift-case-paths 1.10.0, swift-navigation
    // 2.11.2, swift-composable-architecture 1.26.2, swift-dependencies 1.17.2, swift-perception 2.0.12,
    // swift-macro-testing 0.7.0, swift-snapshot-testing 1.19.7, and SwiftPM 6.4's prebuilts tests). The expectations
    // follow SwiftPM main with swift-build, which links MacroSupport into every macOS module that uses swift-syntax and
    // builds swift-syntax from source for other platforms. Tuist can't pass the prebuilt's settings on to the targets of
    // the workspace's projects, so where those reach a module that uses swift-syntax, it keeps source swift-syntax.

    /// An app that depends on The Composable Architecture: every macro links the prebuilt, and swift-navigation's macro
    /// takes the prebuilt of swift-case-paths' `CasePathsMacrosSupport`, which links it on macOS only. No library that
    /// apps link uses swift-syntax, so neither the app nor its tests, which may use the snapshot and macro testing
    /// libraries that do, change that.
    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider,
        arguments: [
            (["ComposableArchitecture"], true),
            (["ComposableArchitecture", "InlineSnapshotTesting", "MacroTesting"], true),
            (["ComposableArchitecture"], false),
        ] as [(Set<String>, Bool)]
    ) func map_whenAppDependsOnTheComposableArchitecture_linksThePrebuiltLikeSwiftBuild(
        externalDependencyNames: Set<String>,
        enablesCasePathsTrait: Bool
    ) async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let packageInfos = composableArchitecturePackageInfos()
        try await makePackageDirectories(basePath: basePath, packageInfos: packageInfos)

        let projects = try await mapPackages(
            basePath: basePath,
            packageInfos: packageInfos,
            externalDependencyNames: externalDependencyNames,
            enabledTraits: ["swift-navigation": enablesCasePathsTrait ? ["CasePaths"] : []],
            prebuiltProducts: swiftSyntaxProducts
        )

        for (package, macro) in [
            ("swift-case-paths", "CasePathsMacros"),
            ("swift-navigation", "SwiftNavigationMacros"),
            ("swift-composable-architecture", "ComposableArchitectureMacros"),
            ("swift-dependencies", "DependenciesMacrosPlugin"),
            ("swift-perception", "PerceptionMacros"),
        ] {
            expectSwiftSyntaxPrebuiltOnEveryPlatform(try target(macro, in: package, of: projects))
        }
        let support = try target("CasePathsMacrosSupport", in: "swift-case-paths", of: projects)
        expectMacOSOnlySwiftSyntaxPrebuiltSettings(support)
        #expect(Set(support.dependencies) == Set([
            "SwiftSyntaxMacros", "SwiftCompilerPlugin", "SwiftDiagnostics", "SwiftSyntax", "SwiftSyntaxBuilder",
        ].map { ProjectDescription.TargetDependency.external(name: $0, condition: nonMacOSPlatformCondition) }))
        let navigationMacros = try target("SwiftNavigationMacros", in: "swift-navigation", of: projects)
        #expect(navigationMacros.dependencies
            .contains(.external(name: "CasePathsMacrosSupport", condition: nil)) == enablesCasePathsTrait)
        for (package, library) in [
            ("swift-case-paths", "CasePaths"),
            ("swift-navigation", "SwiftNavigation"),
            ("swift-navigation", "SwiftUINavigation"),
            ("swift-composable-architecture", "ComposableArchitecture"),
            ("swift-dependencies", "Dependencies"),
            ("swift-dependencies", "DependenciesMacros"),
            ("swift-perception", "Perception"),
            ("swift-macro-testing", "MacroTesting"),
            ("swift-snapshot-testing", "InlineSnapshotTesting"),
        ] {
            expectNoSwiftSyntaxPrebuiltSettings(try target(library, in: package, of: projects))
        }
    }

    /// A local macro package whose macro tests use swift-macro-testing, as pointfree's packages do. swift-build links
    /// the prebuilt into the macro, its tests, and on macOS, `MacroTesting` and `InlineSnapshotTesting`, which the tests
    /// link. When the workspace's own tests link `InlineSnapshotTesting` too, Tuist can't pass the prebuilt on to them,
    /// so the snapshot and macro testing libraries, and the macro tests and macro that link them, keep source swift-syntax.
    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider,
        arguments: [([], true), (["InlineSnapshotTesting"], false)] as [(Set<String>, Bool)]
    ) func map_whenLocalMacroTestsUseMacroTesting_linksThePrebuiltLikeSwiftBuild(
        externalDependencyNames: Set<String>,
        linksPrebuilt: Bool
    ) async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        var packageInfos = composableArchitecturePackageInfos().filter {
            ["swift-macro-testing", "swift-snapshot-testing"].contains($0.key)
        }
        packageInfos["my-macros"] = .test(
            name: "my-macros",
            products: [packageLibrary("MyLibrary")],
            targets: [
                .test(name: "MyLibrary", dependencies: [.target(name: "MyMacros", condition: nil)]),
                .test(name: "MyMacros", type: .macro, dependencies: syntax("SwiftSyntaxMacros", "SwiftCompilerPlugin")),
                .test(
                    name: "MyMacrosTests",
                    type: .test,
                    dependencies: [
                        .target(name: "MyMacros", condition: nil),
                        product("MacroTesting", "swift-macro-testing"),
                    ] + syntax("SwiftSyntaxMacrosTestSupport")
                ),
            ],
            platforms: [.ios, .macos]
        )
        try await makePackageDirectories(basePath: basePath, packageInfos: packageInfos)

        let projects = try await mapPackages(
            basePath: basePath,
            packageInfos: packageInfos,
            externalDependencyNames: externalDependencyNames,
            localPackages: ["my-macros"],
            prebuiltProducts: swiftSyntaxProducts
        )

        let macro = try target("MyMacros", in: "my-macros", of: projects)
        let macroTests = try target("MyMacrosTests", in: "my-macros", of: projects)
        let macroTesting = try target("MacroTesting", in: "swift-macro-testing", of: projects)
        let inlineSnapshotTesting = try target("InlineSnapshotTesting", in: "swift-snapshot-testing", of: projects)
        if linksPrebuilt {
            expectSwiftSyntaxPrebuiltOnEveryPlatform(macro)
            expectSwiftSyntaxPrebuiltOnEveryPlatform(macroTests)
            expectMacOSOnlySwiftSyntaxPrebuiltSettings(macroTesting)
            expectMacOSOnlySwiftSyntaxPrebuiltSettings(inlineSnapshotTesting)
        } else {
            for target in [macro, macroTests, macroTesting, inlineSnapshotTesting] {
                expectNoSwiftSyntaxPrebuiltSettings(target)
            }
        }
        expectNoSwiftSyntaxPrebuiltSettings(try target("MyLibrary", in: "my-macros", of: projects))
    }

    /// SwiftPM 6.4's `testIndirectLibrary` and `testLeakyLibrary`: a macro uses another package's library, which uses
    /// swift-syntax through a library of its own. Only macros reach them, so like swift-build, they link the prebuilt on
    /// macOS. Once apps build them too, because the macro's package exports a library that uses them (`exported`),
    /// another package's library uses them (`otherPackage`), or the workspace's projects link them (`project`), they and
    /// the macro keep source swift-syntax.
    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider,
        arguments: [nil, "exported", "otherPackage", "project"] as [String?]
    ) func map_whenMacroUsesLibraryOfAnotherPackage_linksThePrebuiltLikeSwiftPM(leak: String?) async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let leaks = leak == "exported"
        var packageInfos: [String: PackageInfo] = [
            "foo": .test(
                name: "foo",
                products: [.init(name: "Library", type: .library(.automatic), targets: leaks ? ["Foo", "Leaking"] : ["Foo"])],
                targets: [
                    .test(
                        name: "FooMacros",
                        type: .macro,
                        dependencies: syntax("SwiftSyntaxMacros", "SwiftCompilerPlugin") + [product("Intermediate", "library")]
                    ),
                    .test(name: "Foo", dependencies: [.target(name: "FooMacros", condition: nil)]),
                    .test(
                        name: "FooTests",
                        type: .test,
                        dependencies: [.target(name: "FooMacros", condition: nil)] + syntax("SwiftSyntaxMacrosTestSupport")
                    ),
                ] + (leaks ? [.test(name: "Leaking", dependencies: [product("Intermediate", "library")])] : []),
                platforms: [.ios, .macos]
            ),
            "library": .test(
                name: "library",
                products: [packageLibrary("Intermediate")],
                targets: [
                    .test(name: "Base", dependencies: syntax("SwiftSyntaxMacros")),
                    .test(name: "Intermediate", dependencies: [.target(name: "Base", condition: nil)]),
                ],
                platforms: [.ios, .macos]
            ),
        ]
        if leak == "otherPackage" {
            packageInfos["app-kit"] = .test(
                name: "app-kit",
                products: [packageLibrary("AppKitLibrary")],
                targets: [.test(name: "AppKitLibrary", dependencies: [product("Intermediate", "library")])],
                platforms: [.ios, .macos]
            )
        }
        try await makePackageDirectories(basePath: basePath, packageInfos: packageInfos)

        let projects = try await mapPackages(
            basePath: basePath,
            packageInfos: packageInfos,
            externalDependencyNames: leak == "project" ? ["Intermediate"] : [],
            localPackages: ["foo"],
            prebuiltProducts: swiftSyntaxProducts
        )

        let fooMacros = try target("FooMacros", in: "foo", of: projects)
        let fooTests = try target("FooTests", in: "foo", of: projects)
        let base = try target("Base", in: "library", of: projects)
        let intermediate = try target("Intermediate", in: "library", of: projects)
        if leak != nil {
            for target in [fooMacros, fooTests, base, intermediate] {
                expectNoSwiftSyntaxPrebuiltSettings(target)
            }
        } else {
            expectSwiftSyntaxPrebuiltOnEveryPlatform(fooMacros)
            expectSwiftSyntaxPrebuiltOnEveryPlatform(fooTests)
            expectMacOSOnlySwiftSyntaxPrebuiltSettings(base)
            expectMacOSOnlySwiftSyntaxPrebuiltSettings(intermediate)
        }
        expectNoSwiftSyntaxPrebuiltSettings(try target("Foo", in: "foo", of: projects))
    }

    /// A package's library that uses swift-syntax outside its macros' closure, which another package's library links,
    /// builds into apps with source swift-syntax, as it did before. Only libraries that macros alone consume link the
    /// prebuilt, so this one doesn't, and the package's macros keep linking it.
    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_whenAnotherPackagesLibraryUsesSwiftSyntaxLibraryOfMacroPackage_keepsThePrebuiltForTheMacros() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let packageInfos: [String: PackageInfo] = [
            "p-macros": .test(
                name: "p-macros",
                products: [packageLibrary("PMacrosLibrary"), packageLibrary("PSyntaxKit")],
                targets: [
                    .test(name: "PMacrosLibrary", dependencies: [.target(name: "PMacros", condition: nil)]),
                    .test(name: "PMacros", type: .macro, dependencies: syntax("SwiftSyntaxMacros", "SwiftCompilerPlugin")),
                    .test(name: "PSyntaxKit", dependencies: syntax("SwiftSyntax")),
                ],
                platforms: [.ios, .macos]
            ),
            "q-kit": .test(
                name: "q-kit",
                products: [packageLibrary("QKit")],
                targets: [.test(name: "QKit", dependencies: [product("PSyntaxKit", "p-macros")])],
                platforms: [.ios, .macos]
            ),
        ]
        try await makePackageDirectories(basePath: basePath, packageInfos: packageInfos)

        let projects = try await mapPackages(
            basePath: basePath,
            packageInfos: packageInfos,
            prebuiltProducts: swiftSyntaxProducts
        )

        expectSwiftSyntaxPrebuiltOnEveryPlatform(try target("PMacros", in: "p-macros", of: projects))
        let syntaxKit = try target("PSyntaxKit", in: "p-macros", of: projects)
        #expect(syntaxKit.dependencies == [.external(name: "SwiftSyntax", condition: nil)])
        expectNoSwiftSyntaxPrebuiltSettings(syntaxKit)
        expectNoSwiftSyntaxPrebuiltSettings(try target("QKit", in: "q-kit", of: projects))
    }

    // MARK: - Consumers in other packages

    /// SwiftPM resolves a by-name dependency that names no target of its package to the product of that name in one of
    /// the package's dependencies, so Tuist counts it like a product dependency. A product that only a macro consumes,
    /// by name or not, links the prebuilt on macOS. One that an app library consumes by name keeps source swift-syntax,
    /// and so does a macro that consumes it by name while an app library consumes it as a product.
    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider,
        arguments: ["macroOnlyByName", "appByName", "macroByNameAppByProduct"]
    ) func map_whenByNameDependencyConsumesProductOfAnotherPackage_countsItLikeSwiftPM(consumers: String) async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let macroDependency: PackageInfo.Target.Dependency = consumers == "appByName"
            ? product("SyntaxUtils", "SyntaxUtils")
            : .byName(name: "SyntaxUtils", condition: nil)
        var packageInfos: [String: PackageInfo] = [
            // Keyed by the identity of its URL, while its manifest names it after its product, as by-name requires.
            "syntax-utils": .test(
                name: "SyntaxUtils",
                products: [packageLibrary("SyntaxUtils")],
                targets: [.test(name: "SyntaxUtils", dependencies: syntax("SwiftSyntax"))],
                platforms: [.ios, .macos]
            ),
            "labels": .test(
                name: "labels",
                products: [packageLibrary("Labels")],
                targets: [
                    .test(name: "Labels", dependencies: [.target(name: "LabelsMacros", condition: nil)]),
                    .test(
                        name: "LabelsMacros",
                        type: .macro,
                        dependencies: syntax("SwiftSyntaxMacros", "SwiftCompilerPlugin") + [macroDependency]
                    ),
                ],
                platforms: [.ios, .macos]
            ),
        ]
        if consumers != "macroOnlyByName" {
            let appDependency: PackageInfo.Target.Dependency = consumers == "appByName"
                ? .byName(name: "SyntaxUtils", condition: nil)
                : product("SyntaxUtils", "SyntaxUtils")
            packageInfos["reporting"] = .test(
                name: "reporting",
                products: [packageLibrary("Reporting")],
                targets: [.test(name: "Reporting", dependencies: [appDependency])],
                platforms: [.ios, .macos]
            )
        }
        try await makePackageDirectories(basePath: basePath, packageInfos: packageInfos)

        let projects = try await mapPackages(
            basePath: basePath,
            packageInfos: packageInfos,
            prebuiltProducts: swiftSyntaxProducts
        )

        let macro = try target("LabelsMacros", in: "labels", of: projects)
        let utils = try target("SyntaxUtils", in: "syntax-utils", of: projects)
        if consumers == "macroOnlyByName" {
            expectSwiftSyntaxPrebuiltOnEveryPlatform(macro)
            expectMacOSOnlySwiftSyntaxPrebuiltSettings(utils)
            #expect(utils.dependencies == [.external(name: "SwiftSyntax", condition: nonMacOSPlatformCondition)])
        } else {
            expectNoSwiftSyntaxPrebuiltSettings(macro)
            #expect(macro.dependencies.contains(.external(name: "SwiftSyntaxMacros", condition: nil)))
            expectNoSwiftSyntaxPrebuiltSettings(utils)
            #expect(utils.dependencies == [.external(name: "SwiftSyntax", condition: nil)])
            expectNoSwiftSyntaxPrebuiltSettings(try target("Reporting", in: "reporting", of: projects))
        }
    }

    /// A macro package `p` whose macro uses a helper package's library, and whose own library `PL`, which uses
    /// swift-syntax outside the macro's closure, another package's library links. `PL` builds into apps with source
    /// swift-syntax, but that doesn't stop the macro, or the helper that only it uses, from linking the prebuilt.
    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_whenAppLibraryLinksLibraryOfMacroPackageUsingHelperPackage_keepsThePrebuiltForTheMacro() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let packageInfos: [String: PackageInfo] = [
            "p": .test(
                name: "p",
                products: [packageLibrary("PMacrosLibrary"), .init(name: "PL", type: .library(.automatic), targets: ["L"])],
                targets: [
                    .test(name: "PMacrosLibrary", dependencies: [.target(name: "M", condition: nil)]),
                    .test(
                        name: "M",
                        type: .macro,
                        dependencies: syntax("SwiftSyntaxMacros", "SwiftCompilerPlugin") + [product("HP", "h")]
                    ),
                    .test(name: "L", dependencies: syntax("SwiftParser")),
                ],
                platforms: [.ios, .macos]
            ),
            "h": .test(
                name: "h",
                products: [.init(name: "HP", type: .library(.automatic), targets: ["HT"])],
                targets: [.test(name: "HT", dependencies: syntax("SwiftSyntax"))],
                platforms: [.ios, .macos]
            ),
            "r": .test(
                name: "r",
                products: [packageLibrary("X")],
                targets: [.test(name: "X", dependencies: [product("PL", "p")])],
                platforms: [.ios, .macos]
            ),
        ]
        try await makePackageDirectories(basePath: basePath, packageInfos: packageInfos)

        let projects = try await mapPackages(
            basePath: basePath,
            packageInfos: packageInfos,
            prebuiltProducts: swiftSyntaxProducts
        )

        expectSwiftSyntaxPrebuiltOnEveryPlatform(try target("M", in: "p", of: projects))
        expectMacOSOnlySwiftSyntaxPrebuiltSettings(try target("HT", in: "h", of: projects))
        let library = try target("L", in: "p", of: projects)
        #expect(library.dependencies == [.external(name: "SwiftParser", condition: nil)])
        expectNoSwiftSyntaxPrebuiltSettings(library)
        expectNoSwiftSyntaxPrebuiltSettings(try target("X", in: "r", of: projects))
    }

    /// An app library's dependency on a product that links the prebuilt on macOS only counts when the build uses it: its
    /// traits are enabled and Tuist supports one of its platforms.
    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider,
        arguments: [
            (.init(platformNames: [], config: nil, traits: ["Disabled"]), false),
            (.init(platformNames: ["linux"], config: nil, traits: nil), false),
            (.init(platformNames: [], config: nil, traits: ["Enabled"]), true),
            (nil, true),
        ] as [(PackageInfo.PackageConditionDescription?, Bool)]
    ) func map_whenAppLibraryConsumesMacroOnlyProductUnderCondition_keepsSourceOnlyWhenTheBuildUsesIt(
        condition: PackageInfo.PackageConditionDescription?,
        keepsSource: Bool
    ) async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let packageInfos: [String: PackageInfo] = [
            "c-case-paths": casePathsPackageInfo(name: "c-case-paths"),
            "app-kit": .test(
                name: "app-kit",
                products: [packageLibrary("AppKitLibrary")],
                targets: [.test(
                    name: "AppKitLibrary",
                    dependencies: [.product(
                        name: "CasePathsMacrosSupport",
                        package: "c-case-paths",
                        moduleAliases: nil,
                        condition: condition
                    )]
                )],
                platforms: [.ios, .macos]
            ),
        ]
        try await makePackageDirectories(basePath: basePath, packageInfos: packageInfos)

        let projects = try await mapPackages(
            basePath: basePath,
            packageInfos: packageInfos,
            enabledTraits: ["app-kit": ["Enabled"]]
        )

        let support = try target("CasePathsMacrosSupport", in: "c-case-paths", of: projects)
        if keepsSource {
            #expect(support.dependencies == [.external(name: "SwiftSyntax", condition: nil)])
            expectNoSwiftSyntaxPrebuiltSettings(support)
        } else {
            expectMacOSOnlySwiftSyntaxPrebuiltSettings(support)
        }
    }

    /// Registry packages are keyed by `scope.name`, while manifests can reference them by name, and a local package that
    /// overrides a registry package is keyed by name while manifests reference its `scope.name`. Either way, the
    /// consumers of its products count.
    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider,
        arguments: [
            ("pointfreeco.swift-case-paths", "swift-case-paths", false),
            ("pointfreeco.swift-case-paths", "swift-case-paths", true),
            ("swift-case-paths", "pointfreeco.swift-case-paths", false),
            ("swift-case-paths", "pointfreeco.swift-case-paths", true),
        ]
    ) func map_whenProductIsReferencedByAnotherSpellingOfItsPackage_countsItsConsumers(
        packageKey: String,
        reference: String,
        appConsumesSupport: Bool
    ) async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        var packageInfos: [String: PackageInfo] = [
            packageKey: casePathsPackageInfo(name: "swift-case-paths"),
            "navigation": .test(
                name: "navigation",
                products: [packageLibrary("Navigation")],
                targets: [
                    .test(name: "Navigation", dependencies: [.target(name: "NavigationMacros", condition: nil)]),
                    .test(
                        name: "NavigationMacros",
                        type: .macro,
                        dependencies: [swiftSyntaxProductDependency, product("CasePathsMacrosSupport", reference)]
                    ),
                ],
                platforms: [.ios, .macos]
            ),
        ]
        if appConsumesSupport {
            packageInfos["app-kit"] = .test(
                name: "app-kit",
                products: [packageLibrary("AppKitLibrary")],
                targets: [.test(name: "AppKitLibrary", dependencies: [product("CasePathsMacrosSupport", reference)])],
                platforms: [.ios, .macos]
            )
        }
        try await makePackageDirectories(basePath: basePath, packageInfos: packageInfos)

        let projects = try await mapPackages(basePath: basePath, packageInfos: packageInfos)

        let support = try target("CasePathsMacrosSupport", in: packageKey, of: projects)
        let navigationMacros = try target("NavigationMacros", in: "navigation", of: projects)
        if appConsumesSupport {
            expectNoSwiftSyntaxPrebuiltSettings(support)
            expectNoSwiftSyntaxPrebuiltSettings(navigationMacros)
        } else {
            expectMacOSOnlySwiftSyntaxPrebuiltSettings(support)
            expectSwiftSyntaxPrebuiltOnEveryPlatform(navigationMacros)
        }
    }

    /// A test of a local package that links one of its libraries builds for the apps' platforms, so when Tuist maps local
    /// packages' tests, its dependency on a product that links the prebuilt on macOS keeps that product's package on
    /// source swift-syntax. Remote packages' tests aren't mapped, so theirs doesn't.
    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider,
        arguments: [true, false]
    ) func map_whenPackageTestConsumesMacroOnlyProduct_keepsSourceOnlyWhenTheTestIsMapped(local: Bool) async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let packageInfos: [String: PackageInfo] = [
            "c-case-paths": casePathsPackageInfo(name: "c-case-paths"),
            "app-lib": .test(
                name: "app-lib",
                products: [packageLibrary("AppLib")],
                targets: [
                    .test(name: "AppLib"),
                    .test(
                        name: "AppLibTests",
                        type: .test,
                        dependencies: [
                            .target(name: "AppLib", condition: nil),
                            product("CasePathsMacrosSupport", "c-case-paths"),
                        ]
                    ),
                ],
                platforms: [.ios, .macos]
            ),
        ]
        try await makePackageDirectories(basePath: basePath, packageInfos: packageInfos)

        let projects = try await mapPackages(
            basePath: basePath,
            packageInfos: packageInfos,
            localPackages: local ? ["app-lib"] : []
        )

        let support = try target("CasePathsMacrosSupport", in: "c-case-paths", of: projects)
        if local {
            #expect(support.dependencies == [.external(name: "SwiftSyntax", condition: nil)])
            expectNoSwiftSyntaxPrebuiltSettings(support)
        } else {
            expectMacOSOnlySwiftSyntaxPrebuiltSettings(support)
        }
    }

    /// Products that share a target share its prebuilts, so an app library that consumes one of them keeps the target, and
    /// the macro that consumes the other, on source swift-syntax.
    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider,
        arguments: [false, true]
    ) func map_whenProductsShareATarget_countsTheConsumersOfEach(appConsumesOtherProduct: Bool) async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        var packageInfos: [String: PackageInfo] = [
            "helpers": .test(
                name: "helpers",
                products: [
                    .init(name: "HelpersA", type: .library(.automatic), targets: ["Helpers"]),
                    .init(name: "HelpersB", type: .library(.automatic), targets: ["Helpers"]),
                ],
                targets: [.test(name: "Helpers", dependencies: syntax("SwiftSyntax"))],
                platforms: [.ios, .macos]
            ),
            "m": .test(
                name: "m",
                products: [packageLibrary("MLibrary")],
                targets: [
                    .test(name: "MLibrary", dependencies: [.target(name: "MMacros", condition: nil)]),
                    .test(
                        name: "MMacros",
                        type: .macro,
                        dependencies: syntax("SwiftSyntaxMacros", "SwiftCompilerPlugin") + [product("HelpersA", "helpers")]
                    ),
                ],
                platforms: [.ios, .macos]
            ),
        ]
        if appConsumesOtherProduct {
            packageInfos["app"] = .test(
                name: "app",
                products: [packageLibrary("AppLibrary")],
                targets: [.test(name: "AppLibrary", dependencies: [product("HelpersB", "helpers")])],
                platforms: [.ios, .macos]
            )
        }
        try await makePackageDirectories(basePath: basePath, packageInfos: packageInfos)

        let projects = try await mapPackages(
            basePath: basePath,
            packageInfos: packageInfos,
            prebuiltProducts: swiftSyntaxProducts
        )

        let helpers = try target("Helpers", in: "helpers", of: projects)
        let macro = try target("MMacros", in: "m", of: projects)
        if appConsumesOtherProduct {
            #expect(helpers.dependencies == [.external(name: "SwiftSyntax", condition: nil)])
            expectNoSwiftSyntaxPrebuiltSettings(helpers)
            expectNoSwiftSyntaxPrebuiltSettings(macro)
        } else {
            expectMacOSOnlySwiftSyntaxPrebuiltSettings(helpers)
            expectSwiftSyntaxPrebuiltOnEveryPlatform(macro)
        }
    }

    /// The swift-syntax products that the real packages use, all of which SwiftPM's prebuilt replaces.
    private var swiftSyntaxProducts: [String] {
        [
            "SwiftCompilerPlugin", "SwiftDiagnostics", "SwiftOperators", "SwiftParser", "SwiftParserDiagnostics",
            "SwiftSyntax", "SwiftSyntaxBuilder", "SwiftSyntaxMacros", "SwiftSyntaxMacrosTestSupport",
        ]
    }

    private func syntax(_ products: String...) -> [PackageInfo.Target.Dependency] {
        products.map { .product(name: $0, package: "swift-syntax", moduleAliases: nil, condition: nil) }
    }

    private func product(_ name: String, _ package: String, traits: [String]? = nil) -> PackageInfo.Target.Dependency {
        .product(
            name: name,
            package: package,
            moduleAliases: nil,
            condition: traits.map { .init(platformNames: [], config: nil, traits: $0) }
        )
    }

    private func packageLibrary(_ name: String) -> PackageInfo.Product {
        .init(name: name, type: .library(.automatic), targets: [name])
    }

    private func target(
        _ name: String,
        in package: String,
        of projects: [String: ProjectDescription.Project],
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> ProjectDescription.Target {
        try #require(projects[package]?.targets.first(where: { $0.name == name }), sourceLocation: sourceLocation)
    }

    private func expectSwiftSyntaxPrebuiltOnEveryPlatform(
        _ target: ProjectDescription.Target,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            target.settings?.base["OTHER_LDFLAGS"] == .array(["$(inherited)", "-lSwiftSyntax"]),
            sourceLocation: sourceLocation
        )
        let swiftSyntaxDependencies = target.dependencies.filter { dependency in
            guard case let .external(name, _) = dependency else { return false }
            return swiftSyntaxProducts.contains(name)
        }
        #expect(swiftSyntaxDependencies.isEmpty, sourceLocation: sourceLocation)
    }

    /// The parts of the manifests of The Composable Architecture and the packages it and pointfree's macro tests depend on
    /// that relate to swift-syntax, at the versions the section lists.
    private func composableArchitecturePackageInfos() -> [String: PackageInfo] {
        [
            "swift-case-paths": .test(
                name: "swift-case-paths",
                products: [
                    packageLibrary("CasePaths"),
                    packageLibrary("CasePathsCore"),
                    packageLibrary("CasePathsMacrosSupport"),
                ],
                targets: [
                    .test(
                        name: "CasePaths",
                        dependencies: [
                            .target(name: "CasePathsCore", condition: nil),
                            .target(name: "CasePathsMacros", condition: nil),
                        ]
                    ),
                    .test(name: "CasePathsCore"),
                    .test(
                        name: "CasePathsMacrosSupport",
                        dependencies: syntax(
                            "SwiftSyntaxMacros", "SwiftCompilerPlugin", "SwiftDiagnostics", "SwiftSyntax", "SwiftSyntaxBuilder"
                        )
                    ),
                    .test(
                        name: "CasePathsMacros",
                        type: .macro,
                        dependencies: [.target(name: "CasePathsMacrosSupport", condition: nil)]
                            + syntax("SwiftSyntaxMacros", "SwiftCompilerPlugin", "SwiftSyntax")
                    ),
                    .test(
                        name: "CasePathsTests",
                        type: .test,
                        dependencies: [
                            .target(name: "CasePaths", condition: nil), .target(name: "CasePathsMacrosSupport", condition: nil),
                        ]
                    ),
                ],
                platforms: [.ios, .macos]
            ),
            "swift-navigation": .test(
                name: "swift-navigation",
                products: [packageLibrary("SwiftNavigation"), packageLibrary("SwiftUINavigation")],
                targets: [
                    .test(
                        name: "SwiftNavigation",
                        dependencies: [
                            .target(name: "SwiftNavigationMacros", condition: nil),
                            product("CasePaths", "swift-case-paths", traits: ["CasePaths"]),
                        ]
                    ),
                    .test(
                        name: "SwiftNavigationMacros",
                        type: .macro,
                        dependencies: [product("CasePathsMacrosSupport", "swift-case-paths", traits: ["CasePaths"])] + syntax(
                            "SwiftCompilerPlugin", "SwiftDiagnostics", "SwiftSyntax", "SwiftSyntaxBuilder", "SwiftSyntaxMacros"
                        )
                    ),
                    .test(
                        name: "SwiftUINavigation",
                        dependencies: [
                            .target(name: "SwiftNavigation", condition: nil),
                            product("CasePaths", "swift-case-paths", traits: ["CasePaths"]),
                        ]
                    ),
                    .test(
                        name: "SwiftNavigationMacrosTests",
                        type: .test,
                        dependencies: [
                            .target(name: "SwiftNavigationMacros", condition: nil), product(
                                "MacroTesting",
                                "swift-macro-testing"
                            ),
                        ]
                    ),
                ],
                platforms: [.ios, .macos]
            ),
            "swift-composable-architecture": .test(
                name: "swift-composable-architecture",
                products: [packageLibrary("ComposableArchitecture")],
                targets: [
                    .test(
                        name: "ComposableArchitecture",
                        dependencies: [
                            .target(name: "ComposableArchitectureMacros", condition: nil),
                            product("CasePaths", "swift-case-paths"),
                            product("Dependencies", "swift-dependencies"),
                            product("DependenciesMacros", "swift-dependencies"),
                            product("Perception", "swift-perception"),
                            product("SwiftUINavigation", "swift-navigation"),
                        ]
                    ),
                    .test(
                        name: "ComposableArchitectureMacros",
                        type: .macro,
                        dependencies: syntax("SwiftSyntaxMacros", "SwiftCompilerPlugin")
                    ),
                ],
                platforms: [.ios, .macos]
            ),
            "swift-dependencies": .test(
                name: "swift-dependencies",
                products: [packageLibrary("Dependencies"), packageLibrary("DependenciesMacros")],
                targets: [
                    .test(name: "Dependencies"),
                    .test(name: "DependenciesMacros", dependencies: [.target(name: "DependenciesMacrosPlugin", condition: nil)]),
                    .test(
                        name: "DependenciesMacrosPlugin",
                        type: .macro,
                        dependencies: syntax("SwiftSyntaxMacros", "SwiftCompilerPlugin")
                    ),
                ],
                platforms: [.ios, .macos]
            ),
            "swift-perception": .test(
                name: "swift-perception",
                products: [packageLibrary("Perception"), packageLibrary("PerceptionCore")],
                targets: [
                    .test(
                        name: "Perception",
                        dependencies: [
                            .target(name: "PerceptionCore", condition: nil),
                            .target(name: "PerceptionMacros", condition: nil),
                        ]
                    ),
                    .test(name: "PerceptionCore"),
                    .test(
                        name: "PerceptionMacros",
                        type: .macro,
                        dependencies: syntax("SwiftSyntaxMacros", "SwiftCompilerPlugin")
                    ),
                ],
                platforms: [.ios, .macos]
            ),
            "swift-macro-testing": .test(
                name: "swift-macro-testing",
                products: [packageLibrary("MacroTesting")],
                targets: [
                    .test(
                        name: "MacroTesting",
                        dependencies: [product("InlineSnapshotTesting", "swift-snapshot-testing")] + syntax(
                            "SwiftDiagnostics", "SwiftOperators", "SwiftParserDiagnostics", "SwiftSyntaxMacros",
                            "SwiftSyntaxMacrosTestSupport"
                        )
                    ),
                ],
                platforms: [.ios, .macos]
            ),
            "swift-snapshot-testing": .test(
                name: "swift-snapshot-testing",
                products: [packageLibrary("SnapshotTesting"), packageLibrary("InlineSnapshotTesting")],
                targets: [
                    .test(name: "SnapshotTesting"),
                    .test(
                        name: "InlineSnapshotTesting",
                        dependencies: [.target(name: "SnapshotTesting", condition: nil)]
                            + syntax("SwiftParser", "SwiftSyntax", "SwiftSyntaxBuilder")
                    ),
                ],
                platforms: [.ios, .macos]
            ),
        ]
    }

    /// Mirrors swift-case-paths: `CasePaths` uses the `CasePathsMacros` macro, which links the `CasePathsMacrosSupport`
    /// library product.
    private func casePathsPackageInfo(name: String, testTargets: [PackageInfo.Target] = []) -> PackageInfo {
        .test(
            name: name,
            products: [
                .init(name: "CasePaths", type: .library(.automatic), targets: ["CasePaths"]),
                .init(name: "CasePathsMacrosSupport", type: .library(.automatic), targets: ["CasePathsMacrosSupport"]),
            ],
            targets: [
                .test(name: "CasePaths", dependencies: [.target(name: "CasePathsMacros", condition: nil)]),
                .test(
                    name: "CasePathsMacros",
                    type: .macro,
                    dependencies: [.target(name: "CasePathsMacrosSupport", condition: nil), swiftSyntaxProductDependency]
                ),
                .test(name: "CasePathsMacrosSupport", dependencies: [swiftSyntaxProductDependency]),
            ] + testTargets,
            platforms: [.ios, .macos]
        )
    }

    private func makePackageDirectories(basePath: AbsolutePath, packageInfos: [String: PackageInfo]) async throws {
        for (package, packageInfo) in packageInfos {
            for target in packageInfo.targets {
                try await fileSystem.makeDirectory(
                    at: basePath.appending(components: package, target.type == .test ? "Tests" : "Sources", target.name)
                )
            }
        }
    }

    /// Maps every package like `SwiftPackageManagerGraphLoader` does, with the prebuilts each package's targets link
    /// across packages.
    private func mapPackages(
        basePath: AbsolutePath,
        packageInfos: [String: PackageInfo],
        externalDependencyNames: Set<String> = [],
        enabledTraits: [String: Set<String>] = [:],
        localPackages: Set<String> = [],
        prebuiltProducts: [String] = ["SwiftSyntax"]
    ) async throws -> [String: ProjectDescription.Project] {
        let packageTypes = Dictionary(uniqueKeysWithValues: packageInfos.keys.map { package in
            (package, swiftSyntaxPrebuiltPackageType(
                origin: localPackages.contains(package) ? .local : .remote,
                basePath: basePath,
                products: prebuiltProducts
            ))
        })
        let includeLocalPackageTestTargets = !localPackages.isEmpty
        let prebuiltTargets = try PackageInfoMapper.prebuiltTargets(
            packageInfos: packageInfos,
            packageTypes: packageTypes,
            enabledTraits: enabledTraits,
            includeLocalPackageTestTargets: includeLocalPackageTestTargets,
            externalDependencyNames: externalDependencyNames
        )
        var projects: [String: ProjectDescription.Project] = [:]
        for (package, packageInfo) in packageInfos {
            projects[package] = try await subject.map(
                packageInfo: packageInfo,
                path: basePath.appending(component: package),
                packageType: packageTypes[package]!.withPrebuiltTargets(prebuiltTargets[package] ?? [:]),
                packageSettings: .test(baseSettings: .default, includeLocalPackageTestTargets: includeLocalPackageTestTargets),
                packageModuleAliases: [:],
                packageProducts: [:],
                enabledTraits: enabledTraits[package] ?? []
            )
        }
        return projects
    }

    private func expectNoSwiftSyntaxPrebuiltSettings(
        _ target: ProjectDescription.Target,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let settings = target.settings?.base ?? [:]
        #expect(settings["OTHER_LDFLAGS"] == nil, sourceLocation: sourceLocation)
        #expect(settings["LIBRARY_SEARCH_PATHS"] == nil, sourceLocation: sourceLocation)
        #expect(!settings.keys.contains(where: { $0.hasPrefix("TUIST_SWIFTPM_PREBUILTS_") }), sourceLocation: sourceLocation)
    }

    private var nonMacOSPlatformCondition: ProjectDescription.PlatformCondition? {
        .when([.ios, .catalyst, .tvos, .watchos, .visionos])
    }

    private func expectMacOSOnlySwiftSyntaxPrebuiltSettings(
        _ target: ProjectDescription.Target,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let settings = target.settings?.base ?? [:]
        for (key, values) in [
            ("OTHER_SWIFT_FLAGS", [
                "-I", "$(SRCROOT)/../.build/prebuilts/swift-syntax/Modules",
                "-I", "$(SRCROOT)/../.build/prebuilts/swift-syntax/include/_SwiftSyntaxCShims",
            ]),
            ("LIBRARY_SEARCH_PATHS", ["$(SRCROOT)/../.build/prebuilts/swift-syntax/lib"]),
            ("LD_RUNPATH_SEARCH_PATHS", ["$(SRCROOT)/../.build/prebuilts/swift-syntax/lib"]),
            ("OTHER_LDFLAGS", ["-lSwiftSyntax"]),
        ] {
            // Mac Catalyst also builds with the macOS SDK, so `[sdk=macosx*]` can't scope these to macOS.
            #expect(
                settings[key] == .array([
                    "$(inherited)",
                    "$(TUIST_SWIFTPM_PREBUILTS_\(key)_$(PLATFORM_NAME)_$(IS_MACCATALYST:default=NO))",
                ]),
                sourceLocation: sourceLocation
            )
            #expect(settings["TUIST_SWIFTPM_PREBUILTS_\(key)_macosx_NO"] == .array(values), sourceLocation: sourceLocation)
        }
    }

    private var swiftSyntaxProductDependency: PackageInfo.Target.Dependency {
        .product(name: "SwiftSyntax", package: "swift-syntax", moduleAliases: nil, condition: nil)
    }

    /// SwiftPM's prebuilt replaces every library product of swift-syntax, so `products` lists the ones a test uses.
    private func swiftSyntaxPrebuiltPackageType(
        origin: PackageType.ExternalOrigin,
        basePath: AbsolutePath,
        products: [String] = ["SwiftSyntax"]
    ) -> PackageType {
        let prebuilt = SwiftPackageManagerPrebuilt(
            identity: "swift-syntax",
            version: "601.0.0",
            libraryName: "SwiftSyntax",
            path: basePath.appending(components: ".build", "prebuilts", "swift-syntax"),
            checkoutPath: nil,
            products: products,
            includePath: nil,
            cModules: ["_SwiftSyntaxCShims"]
        )
        return .external(
            origin: origin,
            artifactPaths: [:],
            packagePrebuilts: ["swift-syntax": Dictionary(uniqueKeysWithValues: products.map { ($0, prebuilt) })]
        )
    }

    private func makeMacroPackageDirectories(
        basePath: AbsolutePath,
        targets: [String] = [],
        testTargets: [String] = []
    ) async throws {
        let paths = [
            "Package/Sources/Library",
            "Package/Sources/MyMacro",
            "Package/Tests/LibraryTests",
            "Package/Tests/MyMacroTests",
        ] + targets.map { "Package/Sources/\($0)" } + testTargets.map { "Package/Tests/\($0)" }
        for path in paths {
            try await fileSystem.makeDirectory(at: basePath.appending(try RelativePath(validating: path)))
        }
    }

    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_whenExternalLocalTestTargetOnlyDependsOnPluginTarget_ignoresTestTarget() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)

        try await fileSystem.makeDirectory(
            at: basePath.appending(try RelativePath(validating: "Package/Tests/PluginTests"))
        )

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageType: .external(
                origin: .local,
                artifactPaths: [:],
                packagePrebuilts: [
                    "swift-syntax": [
                        "SwiftSyntax": SwiftPackageManagerPrebuilt(
                            identity: "swift-syntax",
                            version: "601.0.0",
                            libraryName: "SwiftSyntax",
                            path: basePath.appending(components: ".build", "prebuilts", "swift-syntax"),
                            checkoutPath: nil,
                            products: ["SwiftSyntax"],
                            includePath: nil,
                            cModules: ["_SwiftSyntaxCShims"]
                        ),
                    ],
                ]
            ),
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [],
                    targets: [
                        .test(name: "Plugin", type: .plugin),
                        .test(
                            name: "PluginTests",
                            type: .test,
                            dependencies: [
                                .target(name: "Plugin", condition: nil),
                                .product(
                                    name: "SwiftSyntax",
                                    package: "swift-syntax",
                                    moduleAliases: nil,
                                    condition: nil
                                ),
                            ]
                        ),
                    ],
                    platforms: [.macos]
                ),
            ]
        )

        #expect(project == nil)
    }

    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func map_whenPrebuiltProductDependencyHasUnsupportedCondition_skipsDependency() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)

        try await fileSystem.makeDirectory(
            at: basePath.appending(try RelativePath(validating: "Package/Sources/MyMacro"))
        )

        let project = try await subject.map(
            package: "Package",
            basePath: basePath,
            packageType: .external(
                artifactPaths: [:],
                packagePrebuilts: [
                    "swift-syntax": [
                        "SwiftSyntax": SwiftPackageManagerPrebuilt(
                            identity: "swift-syntax",
                            version: "601.0.0",
                            libraryName: "SwiftSyntax",
                            path: basePath.appending(components: ".build", "prebuilts", "swift-syntax"),
                            checkoutPath: nil,
                            products: ["SwiftSyntax"],
                            includePath: nil,
                            cModules: ["_SwiftSyntaxCShims"]
                        ),
                    ],
                ]
            ),
            packageInfos: [
                "Package": .test(
                    name: "Package",
                    products: [],
                    targets: [
                        .test(
                            name: "MyMacro",
                            type: .macro,
                            dependencies: [
                                .product(
                                    name: "SwiftSyntax",
                                    package: "swift-syntax",
                                    moduleAliases: nil,
                                    condition: .init(platformNames: [], config: "debug")
                                ),
                            ]
                        ),
                    ],
                    platforms: [.macos]
                ),
            ]
        )

        let target = try #require(project?.targets.first(where: { $0.name == "MyMacro" }))
        #expect(target.dependencies.isEmpty)
        #expect(
            target.settings?.base["OTHER_SWIFT_FLAGS"] == .array([
                "$(inherited)",
            ])
        )
        #expect(target.settings?.base["SWIFT_PACKAGE_NAME"] == .string("Package"))
        #expect(target.settings?.base["LIBRARY_SEARCH_PATHS"] == nil)
        #expect(target.settings?.base["OTHER_LDFLAGS"] == nil)
    }
}

extension PackageInfoMapperTests {
    private func generatedStaticLibraryArtifactBundleXCFrameworkPath(
        basePath: AbsolutePath,
        packageName: String,
        targetName: String,
        artifactBundlePath: AbsolutePath
    ) async throws -> AbsolutePath {
        let infoData = try await fileSystem.readFile(at: artifactBundlePath.appending(component: "info.json"))
        let contentHasher = ContentHasher()
        let sourceFingerprint = try contentHasher.hash([
            artifactBundlePath.pathString,
            contentHasher.hash(infoData),
        ])
        return basePath.appending(
            components: Constants.DerivedDirectory.dependenciesDerivedDirectory,
            Constants.DerivedDirectory.dependenciesXCFrameworkDirectory,
            packageName,
            "\(targetName)-\(sourceFingerprint).xcframework"
        )
    }

    private func makeStaticLibraryArtifactBundle(
        at artifactBundlePath: AbsolutePath,
        targetName: String
    ) async throws {
        try await fileSystem.makeDirectory(at: artifactBundlePath.appending(component: "include"))
        try await fileSystem.makeDirectory(at: artifactBundlePath.appending(component: "apple-ios-device"))
        try await fileSystem.makeDirectory(at: artifactBundlePath.appending(component: "apple-ios-simulator"))
        try await fileSystem.makeDirectory(at: artifactBundlePath.appending(component: "linux-x86_64"))

        try await fileSystem.writeText(
            "",
            at: artifactBundlePath.appending(components: "apple-ios-device", "lib\(targetName).a")
        )
        try await fileSystem.writeText(
            "",
            at: artifactBundlePath.appending(components: "apple-ios-simulator", "lib\(targetName).a")
        )
        try await fileSystem.writeText(
            "",
            at: artifactBundlePath.appending(components: "linux-x86_64", "lib\(targetName).a")
        )
        try await fileSystem.writeText(
            "",
            at: artifactBundlePath.appending(components: "include", "\(targetName).h")
        )
        try await fileSystem.writeText(
            "module \(targetName) { header \"\(targetName).h\" export * }",
            at: artifactBundlePath.appending(components: "include", "module.modulemap")
        )
        try await fileSystem.writeText(
            """
            {
              "schemaVersion": "1.0",
              "artifacts": {
                "\(targetName)": {
                  "type": "staticLibrary",
                  "version": "1.0.0",
                  "variants": [
                    {
                      "path": "apple-ios-device/lib\(targetName).a",
                      "supportedTriples": ["arm64-apple-ios"],
                      "staticLibraryMetadata": {
                        "headerPaths": ["include"],
                        "moduleMapPath": "include/module.modulemap"
                      }
                    },
                    {
                      "path": "apple-ios-simulator/lib\(targetName).a",
                      "supportedTriples": ["arm64-apple-ios-simulator", "x86_64-apple-ios-simulator"],
                      "staticLibraryMetadata": {
                        "headerPaths": ["include"],
                        "moduleMapPath": "include/module.modulemap"
                      }
                    },
                    {
                      "path": "linux-x86_64/lib\(targetName).a",
                      "supportedTriples": ["x86_64-unknown-linux-gnu"],
                      "staticLibraryMetadata": {
                        "headerPaths": ["include"],
                        "moduleMapPath": "include/module.modulemap"
                      }
                    }
                  ]
                }
              }
            }
            """,
            at: artifactBundlePath.appending(component: "info.json")
        )
    }
}

private func defaultSpmResources(_ target: String, customPath: String? = nil) -> ProjectDescription.ResourceFileElements {
    let fullPath: String
    if let customPath {
        fullPath = customPath
    } else {
        fullPath = "/Package/Sources/\(target)"
    }
    return [
        "\(fullPath)/**/*.xib",
        "\(fullPath)/**/*.nib",
        "\(fullPath)/**/*.storyboard",
        "\(fullPath)/**/*.xcdatamodeld",
        "\(fullPath)/**/*.xcmappingmodel",
        "\(fullPath)/**/*.xcassets",
        "\(fullPath)/**/*.lproj",
    ]
}

extension PackageInfoMapping {
    fileprivate func map(
        package: String,
        basePath: AbsolutePath = "/",
        packageType: PackageType? = nil,
        packageInfos: [String: PackageInfo] = [:],
        packageSettings: TuistCore.PackageSettings = .test(
            baseSettings: .default
        ),
        packageModuleAliases: [String: [String: String]] = [:],
        packageProducts: [String: [String: [ProjectDescription.TargetDependency]]] = [:],
        enabledTraits: Set<String> = []
    ) async throws -> ProjectDescription.Project? {
        let packageToTargetsToArtifactPaths: [String: [String: AbsolutePath]] = try packageInfos
            .reduce(into: [:]) { packagesResult, element in
                let (packageName, packageInfo) = element
                packagesResult[packageName] = try packageInfo.targets
                    .reduce(into: [String: AbsolutePath]()) { targetsResult, target in
                        guard target.type == .binary else {
                            return
                        }
                        if let path = target.path, !path.hasSuffix(".zip") {
                            targetsResult[target.name] = basePath.appending(
                                try RelativePath(validating: "\(path)")
                            )
                        } else {
                            targetsResult[target.name] = basePath.appending(
                                try RelativePath(validating: "artifacts/\(packageName)/\(target.name).xcframework")
                            )
                        }
                    }
            }

        return try await map(
            packageInfo: packageInfos[package]!,
            path: basePath.appending(component: package),
            packageType: packageType ?? .external(artifactPaths: packageToTargetsToArtifactPaths[package]!),
            packageSettings: packageSettings,
            packageModuleAliases: packageModuleAliases,
            packageProducts: packageProducts,
            enabledTraits: enabledTraits
        )
    }
}

extension PackageInfo.Target {
    fileprivate static func test(
        name: String,
        type: PackageInfo.Target.TargetType = .regular,
        path: String? = nil,
        url: String? = nil,
        sources: [String]? = nil,
        resources: [PackageInfo.Target.Resource] = [],
        exclude: [String] = [],
        dependencies: [PackageInfo.Target.Dependency] = [],
        publicHeadersPath: String? = nil,
        settings: [TargetBuildSettingDescription.Setting] = []
    ) -> Self {
        .init(
            name: name,
            path: path,
            url: url,
            sources: sources,
            resources: resources,
            exclude: exclude,
            dependencies: dependencies,
            publicHeadersPath: publicHeadersPath,
            type: type,
            settings: settings,
            checksum: nil
        )
    }
}

extension ProjectDescription.Project {
    fileprivate static func test(
        name: String,
        options: Options = .options(
            automaticSchemesOptions: .disabled,
            disableBundleAccessors: false,
            disableSynthesizedResourceAccessors: true,
            textSettings: .textSettings(usesTabs: nil, indentWidth: nil, tabWidth: nil, wrapsLines: nil)
        ),
        settings: ProjectDescription.Settings? = nil,
        targets: [ProjectDescription.Target]
    ) -> Self {
        .init(
            name: name,
            options: options,
            settings: settings,
            targets: targets,
            resourceSynthesizers: .default
        )
    }

    fileprivate static func testWithDefaultConfigs(
        name: String,
        options: Options = .options(
            automaticSchemesOptions: .disabled,
            disableBundleAccessors: false,
            disableSynthesizedResourceAccessors: true,
            textSettings: .textSettings(usesTabs: nil, indentWidth: nil, tabWidth: nil, wrapsLines: nil)
        ),
        settings: ProjectDescription.Settings = .settings(
            base: ["SWIFT_VERSION": "5"],
            configurations: [
                .debug(name: .debug),
                .release(name: .release),
            ]
        ),
        customSettings: ProjectDescription.SettingsDictionary = [:],
        targets: [ProjectDescription.Target]
    ) -> Self {
        Project.test(
            name: name,
            options: options,
            settings: DependenciesGraph.swiftpmProjectSettings(
                baseSettings: settings,
                with: customSettings
            ),
            targets: targets
        )
    }
}

extension ProjectDescription.Target {
    fileprivate enum SourceFilesListType {
        case `default`
        case custom(SourceFilesList?)
    }

    fileprivate static func test(
        _ name: String,
        packageName: String = "Package",
        swiftPackageName: String? = nil,
        basePath: AbsolutePath = "/",
        destinations: ProjectDescription.Destinations = Set(Destination.allCases),
        product: ProjectDescription.Product = .staticFramework,
        customProductName: String? = nil,
        customBundleID: String? = nil,
        deploymentTargets: ProjectDescription.DeploymentTargets = .multiplatform(
            iOS: "12.0",
            macOS: "10.13",
            watchOS: "4.0",
            tvOS: "12.0",
            visionOS: "1.0"
        ),
        customSources: SourceFilesListType = .default,
        resources: [ProjectDescription.ResourceFileElement] = [],
        headers: ProjectDescription.Headers? = nil,
        dependencies: [ProjectDescription.TargetDependency] = [],
        baseSettings: ProjectDescription.Settings = .settings(),
        customSettings: ProjectDescription.SettingsDictionary = [
            "OTHER_SWIFT_FLAGS": ["$(inherited)"],
        ],
        moduleMap: String? = nil
    ) -> Self {
        let sources: SourceFilesList?
        var customSettings = customSettings

        switch customSources {
        case let .custom(list):
            sources = list
        case .default:
            let defaultSourcesPath = try! RelativePath(validating: "\(packageName)/Sources/\(name)/**")
            sources =
                .sourceFilesList(globs: [
                    basePath.appending(defaultSourcesPath).pathString,
                ])
        }

        customSettings["SWIFT_PACKAGE_NAME"] = .string(swiftPackageName ?? packageName)

        return ProjectDescription.Target.target(
            name: name,
            destinations: destinations,
            product: product,
            productName: customProductName ?? name,
            bundleId: customBundleID ?? name,
            deploymentTargets: deploymentTargets,
            infoPlist: .default,
            sources: sources,
            resources: resources.isEmpty ? nil : .resources(resources),
            headers: headers,
            dependencies: dependencies,
            settings: DependenciesGraph.spmProductSettings(
                baseSettings: baseSettings,
                with: customSettings,
                moduleMap: moduleMap
            ),
            metadata: .metadata(tags: [TargetTags.swiftPackage])
        )
    }
}

extension ProjectDescription.Headers {
    fileprivate static func spmTarget(
        _ targetBasePath: AbsolutePath,
        projectExcluding: [ProjectDescription.Path] = [],
        publicDirectory: String = "include",
        moduleName: String? = nil,
        moduleMap: AbsolutePath? = nil,
        directoryModule: Bool = false
    ) -> ProjectDescription.Headers {
        let publicPath = targetBasePath.appending(component: publicDirectory)
        let name = moduleName ?? targetBasePath.basename.replacingOccurrences(of: "-", with: "_")
        let glob = "**/*.{h,hh,hpp,h++,hp,hxx,H,ipp,def}"
        return .swiftPackageHeaders(
            public: .list([.glob(.path("\(publicPath.pathString)/\(glob)"))]),
            project: .list([.glob(.path("\(targetBasePath.pathString)/\(glob)"), excluding: projectExcluding)]),
            sourceLayout: .init(
                root: .path(targetBasePath.pathString),
                publicHeaders: .path(publicPath.pathString),
                moduleMap: .path((moduleMap ?? publicPath.appending(component: "module.modulemap")).pathString),
                moduleName: name,
                usesDirectoryModuleMap: directoryModule
            )
        )
    }
}

extension [ProjectDescription.ResourceFileElement] {
    static func defaultResources(
        path: AbsolutePath,
        excluding: [Path] = []
    ) -> Self {
        ["xib", "nib", "storyboard", "xcdatamodeld", "xcmappingmodel", "xcassets", "lproj"]
            .map { file -> ProjectDescription.ResourceFileElement in
                ResourceFileElement.glob(
                    pattern: .path("\(path.appending(component: "**").pathString)/*.\(file)"),
                    excluding: excluding
                )
            }
    }
}

extension Sequence {
    func sorted(by keyPath: KeyPath<Element, some Comparable>) -> [Element] {
        sorted { a, b in
            a[keyPath: keyPath] < b[keyPath: keyPath]
        }
    }
}
