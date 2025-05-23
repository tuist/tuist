import FileSystem
import FileSystemTesting
import Mockable
import Path
import ProjectDescription
import Testing
import TSCUtility
import TuistCore
import TuistSupport
import XcodeGraph
@testable import TuistCoreTesting
@testable import TuistLoader
@testable import TuistSupportTesting

struct PackageInfoMapperTests {
    private var subject: PackageInfoMapper!
    private let fileSystem = FileSystem()

    init() throws {
        let swiftVersionProviderMock = try #require(SwiftVersionProvider.mocked)
        given(swiftVersionProviderMock)
            .swiftVersion()
            .willReturn("5.9")
        subject = PackageInfoMapper()
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func testResolveDependencies_whenProductContainsBinaryTargetWithUrl_mapsToXcframework(
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
                "Target_1": try!
                    .init(validating: "/artifacts/Package/Target_1.xcframework"),
            ]],
            packageModuleAliases: [:]
        )

        #expect(
            resolvedDependencies ==
                [
                    "Product1": [
                        .xcframework(path: "/artifacts/Package/Target_1.xcframework"),
                        .project(target: "Target_2", path: .relativeToManifest(basePath.pathString)),
                    ],
                ]
        )
    }

    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func testResolveDependencies_whenProductContainsBinaryTargetWithPathToXcframework_mapsToXcframework() async throws {
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
            packageModuleAliases: [:]
        )

        #expect(
            resolvedDependencies ==
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
    ) func testResolveDependencies_whenProductContainsBinaryTargetWithPathToZip_mapsToXcframework(
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
                "Target_1": try!
                    .init(validating: "/artifacts/Package/Target_1.xcframework"),
            ]],
            packageModuleAliases: [:]
        )

        #expect(
            resolvedDependencies ==
                [
                    "Product1": [
                        .xcframework(path: "/artifacts/Package/Target_1.xcframework"),
                        .project(target: "Target_2", path: .relativeToManifest(basePath.pathString)),
                    ],
                ]
        )
    }

    @Test(
        .inTemporaryDirectory, .withMockedSwiftVersionProvider
    ) func testResolveDependencies_whenProductContainsBinaryTargetMissingFrom_packageToTargetsToArtifactPaths() async throws {
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
            packageModuleAliases: [:]
        )

        #expect(
            resolvedDependencies ==
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
    ) func testResolveDependencies_whenPackageIDDifferentThanName() async throws {
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
            packageModuleAliases: [:]
        )

        #expect(
            resolvedDependencies ==
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
    ) func testResolveDependencies_whenHasModuleAliases() async throws {
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
            packageModuleAliases: ["Package2": ["Product": "Package2Product"]]
        )

        #expect(
            resolvedDependencies ==
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
    ) func testResolveDependencies_whenDependencyNameContainsDot_mapsToUnderscoreInTargetName(
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
            packageModuleAliases: [:]
        )

        #expect(
            resolvedDependencies ==
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
    ) func testResolveDependencies_whenTargetDependenciesOnTargetHaveConditions() async throws {
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
            packageModuleAliases: [:]
        )

        #expect(
            resolvedDependencies ==
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
    ) func testResolveDependencies_whenTargetDependenciesOnProductHaveConditions() async throws {
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
            packageModuleAliases: [:]
        )

        #expect(
            resolvedDependencies ==
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
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func testMap_whenDynamicAndAutomaticLibraryType_mapsToStaticFramework() async throws {
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
    ) func testMap_whenLegacySwift_usesLegacyIOSVersion() async throws {
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

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func testMap_whenMacCatalyst() async throws {
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

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func testMap_whenAlternativeDefaultSources() async throws {
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
    ) func testMap_whenOnlyBinaries_doesNotCreateProject() async throws {
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
    ) func testMap_whenNameContainsUnderscores_mapsToDashInBundleID() async throws {
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
                        .test("Target_1", basePath: basePath, customBundleID: "Target.1"),
                    ]
                )
        )
    }

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func testMap_whenSettingsDefinesContainsQuotes() async throws {
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
    ) func testMap_whenNameContainsDot_mapsToUnderscoreInTargetName() async throws {
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

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func testMap_whenTargetNotInProduct_ignoresIt() async throws {
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
    ) func testMap_whenTargetIsNotRegular_ignoresTarget() async throws {
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
    ) func testMap_whenProductIsNotLibrary_ignoresProduct() async throws {
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

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func testMap_whenCustomSources() async throws {
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

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func testMap_whenHasResources() async throws {
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
    ) func testMap_whenHasAlreadyIncludedDefaultResources() async throws {
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

    // For more context of this scenario, see: https://github.com/tuist/tuist/issues/7445
    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func testMap_whenResourcesInsideXCFramework() async throws {
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

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func testMap_whenHasDefaultResources() async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        let defaultResourcePaths = try [
            "metal",
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

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func testMap_whenHasHeadersWithCustomModuleMap() async throws {
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

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func testMap_whenHasHeadersWithCustomModuleMapAndTargetWithDashes() async throws {
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

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func testMap_whenHasSystemLibrary() async throws {
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
    ) func testMap_errorWhenSystemLibraryHasMissingModuleMap() async throws {
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

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func testMap_whenHasHeadersWithUmbrellaHeader() async throws {
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

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func testMap_whenDependenciesHaveHeaders() async throws {
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
    ) func testMap_whenExternalDependenciesHaveHeaders() async throws {
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

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func testMap_whenCustomPath() async throws {
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
    ) func testMap_whenDependencyHasHeaders_addsThemToHeaderSearchPath() async throws {
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
                            headers: .headers(
                                public: .list(
                                    [.glob(.path("\(dependencyHeadersPath.pathString)/*.h"))]
                                )
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
    ) func testMap_whenMultipleAvailable_takesMultiple() async throws {
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
    ) func testMap_whenPackageDefinesPlatform_configuresDeploymentTarget() async throws {
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

        dump(project?.targets.first?.destinations)
        dump(other.targets.first?.destinations)

        #expect(
            project ==
                other
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func testMap_whenSettingsContainsCHeaderSearchPath_mapsToHeaderSearchPathsSetting() async throws {
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
    ) func testMap_whenSettingsContainsCXXHeaderSearchPath_mapsToHeaderSearchPathsSetting(
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
    ) func testMap_whenSettingsContainsCDefine_mapsToGccPreprocessorDefinitions() async throws {
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
    ) func testMap_whenSettingsContainsCXXDefine_mapsToGccPreprocessorDefinitions() async throws {
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
    ) func testMap_whenSettingsContainsSwiftDefine_mapsToSwiftActiveCompilationConditions(
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
    ) func testMap_whenSettingsContainsCUnsafeFlags_mapsToOtherCFlags() async throws {
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
    ) func testMap_whenSettingsContainsCXXUnsafeFlags_mapsToOtherCPlusPlusFlags() async throws {
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
    ) func testMap_whenSettingsContainsSwiftUnsafeFlags_mapsToOtherSwiftFlags() async throws {
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
    ) func testMap_whenSettingsContainsEnableUpcomingFeature_mapsToOtherSwiftFlags() async throws {
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
    ) func testMap_whenSettingsContainsEnableExperimentalFeature_mapsToOtherSwiftFlags() async throws {
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
    ) func testMap_whenSettingsContainsSwiftLanguageMode_mapsToOtherSwiftFlags() async throws {
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
                                "OTHER_SWIFT_FLAGS": ["$(inherited)", "-swift-version 5"],
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
    ) func testMap_whenSettingsContainsLinkerUnsafeFlags_mapsToOtherLdFlags() async throws {
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
    ) func testMap_whenConfigurationContainsBaseSettingsDictionary_usesBaseSettings() async throws {
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
    ) func testMap_whenConfigurationContainsTargetSettingsDictionary_mapsToCustomSettings(
    ) async throws {
        let basePath = try #require(FileSystem.temporaryTestDirectory)
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try await fileSystem.makeDirectory(at: sourcesPath)

        let customSettings: XcodeGraph.Settings = .test(
            base: ["CUSTOM_SETTING": .string("CUSTOM_VALUE")],
            configurations: [
                .init(name: "Custom Debug", variant: .debug): .init(
                    settings: ["CUSTOM_SETTING_1": .string("CUSTOM_VALUE_1")],
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
                                        settings: ["CUSTOM_SETTING_1": .string("CUSTOM_VALUE_1")],
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

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func testMap_whenConditionalSetting() async throws {
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
                                    "$(SRCROOT)/Sources/Target1/otherValue",
                                ],
                                "HEADER_SEARCH_PATHS[sdk=appletvsimulator*]": [
                                    "$(inherited)",
                                    "$(SRCROOT)/Sources/Target1/value",
                                    "$(SRCROOT)/Sources/Target1/otherValue",
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
    ) func testMap_whenSettingsContainsLinkedFramework_mapsToSDKDependency() async throws {
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
    ) func testMap_whenSettingsContainsLinkedLibrary_mapsToSDKDependency() async throws {
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

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func testMap_whenTargetDependency_mapsToTargetDependency() async throws {
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
    ) func testMap_whenBinaryTargetDependency_mapsToXcframework() async throws {
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
    ) func testMap_whenTargetByNameDependency_mapsToTargetDependency() async throws {
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
    ) func testMap_whenBinaryTargetURLByNameDependency_mapsToXcFramework() async throws {
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
    ) func testMap_whenBinaryTargetXcframeworkPathByNameDependency_mapsToXcFramework() async throws {
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
    ) func testMap_whenBinaryTargetZipPathByNameDependency_mapsToXcFramework() async throws {
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
    ) func testMap_whenExternalProductDependency_mapsToProjectDependencies() async throws {
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
    ) func testMap_whenExternalByNameProductDependency_mapsToProjectDependencies() async throws {
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
    ) func testMap_whenCustomCVersion_mapsToGccCLanguageStandardSetting() async throws {
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
                    settings: .settings(base: ["GCC_C_LANGUAGE_STANDARD": "c99"]),
                    targets: [
                        .test("Target1", basePath: basePath),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func testMap_whenCustomCXXVersion_mapsToClangCxxLanguageStandardSetting() async throws {
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
                    settings: .settings(base: ["CLANG_CXX_LANGUAGE_STANDARD": "gnu++14"]),
                    targets: [
                        .test("Target1", basePath: basePath),
                    ]
                )
        )
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func testMap_whenCustomSwiftVersion_mapsToSwiftVersionSetting() async throws {
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
    ) func testMap_whenMultipleCustomSwiftVersions_mapsLargestToSwiftVersionSetting() async throws {
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
    ) func testMap_whenMultipleCustomSwiftVersionsAndConfiguredVersion_mapsLargestToSwiftVersionLowerThanConfigured(
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
    ) func testMap_whenDependenciesContainsCustomConfiguration_mapsToProjectWithCustomConfig(
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
    ) func testMap_whenTargetsWithDefaultHardcodedMapping() async throws {
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
        for path in try allTargets
            .map { basePath.appending(try RelativePath(validating: "Package/Sources/\($0)")) }
        {
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
    ) func testMap_whenTargetDependenciesOnTargetHaveConditions() async throws {
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
                            ]
                        ),
                        .test(name: "Dependency1"),
                        .test(name: "Dependency2"),
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

        let projectTargets = project!.targets.sorted(by: \.name)
        let expectedTargets = expected.targets.sorted(by: \.name)
        #expect(projectTargets == expectedTargets)
    }

    @Test(
        .inTemporaryDirectory,
        .withMockedSwiftVersionProvider
    ) func testMap_whenTargetDependenciesOnProductHaveConditions() async throws {
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

        let projectTargets = project!.targets.sorted(by: \.name)
        let expectedTargets = expected.targets.sorted(by: \.name)

        #expect(
            projectTargets ==
                expectedTargets
        )
    }

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func testMap_whenTargetNameContainsSpaces() async throws {
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

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func testMap_whenSwiftPackageHasTestTarget() async throws {
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
                    settings: .settings(),
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
    ) func testMap_whenSwiftPackageHasTestTargetWithExplicitProductDestinations() async throws {
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
                    settings: .settings(),
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
    ) func testMap_whenSwiftPackageHasMultiDependencyTestTargetsWithExplicitProductDestinations(
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
                    settings: .settings(),
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
    ) func testMap_whenSwiftPackageHasTestTargetWithExternalDependency() async throws {
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
                    settings: .settings(),
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

    @Test(.inTemporaryDirectory, .withMockedSwiftVersionProvider) func testMap_whenHasModuleAliases() async throws {
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
    ) func testMap_other_swift_flags_whenSwiftToolsVersionIs_5_8_0() async throws {
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
    ) func testMap_other_swift_flags_whenSwiftToolsVersionIs_5_9_0() async throws {
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
            project?.settings?.base["OTHER_SWIFT_FLAGS"] ==
                .array(["$(inherited)", "-package-name", "Package"])
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
        packageModuleAliases: [String: [String: String]] = [:]
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
            packageModuleAliases: packageModuleAliases
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
        settings: ProjectDescription.Settings = .settings(configurations: [
            .debug(name: .debug),
            .release(name: .release),
        ]),
        customSettings: ProjectDescription.SettingsDictionary = [:],
        targets: [ProjectDescription.Target]
    ) -> Self {
        Project.test(
            name: name,
            options: options,
            settings: DependenciesGraph.swiftpmProjectSettings(
                packageName: name,
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

        switch customSources {
        case let .custom(list):
            sources = list
        case .default:
            // swiftlint:disable:next force_try
            sources =
                .sourceFilesList(globs: [
                    basePath.appending(try! RelativePath(validating: "\(packageName)/Sources/\(name)/**"))
                        .pathString,
                ])
        }

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
            )
        )
    }
}

extension [ProjectDescription.ResourceFileElement] {
    static func defaultResources(
        path: AbsolutePath,
        excluding: [Path] = []
    ) -> Self {
        ["xib", "storyboard", "xcdatamodeld", "xcmappingmodel", "xcassets", "lproj"]
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
