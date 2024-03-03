import ProjectDescription
import TSCBasic
import TSCUtility
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistCoreTesting
@testable import TuistLoader
@testable import TuistSupportTesting

final class PackageInfoMapperTests: TuistUnitTestCase {
    private var subject: PackageInfoMapper!

    override func setUp() {
        super.setUp()

        system.swiftVersionStub = { "5.9.0" }
        subject = PackageInfoMapper()
    }

    override func tearDown() {
        subject = nil

        super.tearDown()
    }

    func testResolveDependencies_whenProductContainsBinaryTarget_mapsToXcframework() throws {
        let basePath = try temporaryPath()
        try fileHandler.createFolder(basePath.appending(try RelativePath(validating: "Sources/Target_1")))
        try fileHandler.createFolder(basePath.appending(try RelativePath(validating: "Sources/Target_2")))
        let resolvedDependencies = try subject.resolveExternalDependencies(
            packageInfos: [
                "Package": .init(
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
            packageToTargetsToArtifactPaths: ["Package": [
                "Target_1": try!
                    .init(validating: "/artifacts/Package/Target_1.xcframework"),
            ]]
        )

        XCTAssertEqual(
            resolvedDependencies,
            [
                "Product1": [
                    .xcframework(path: "/artifacts/Package/Target_1.xcframework"),
                    .project(target: "Target_2", path: .relativeToManifest(basePath.pathString)),
                ],
            ]
        )
    }

    func testResolveDependencies_whenPackageIDDifferentThanName() throws {
        let basePath = try temporaryPath()
        try fileHandler.createFolder(basePath.appending(try RelativePath(validating: "Package/Sources/Target_1")))
        try fileHandler.createFolder(basePath.appending(try RelativePath(validating: "Package/Sources/Target_2")))
        try fileHandler.createFolder(basePath.appending(try RelativePath(validating: "Package2/Sources/Target_2")))
        let resolvedDependencies = try subject.resolveExternalDependencies(
            packageInfos: [
                "Package": .init(
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
                "Package2": .init(
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
            packageToTargetsToArtifactPaths: [:]
        )

        XCTAssertBetterEqual(
            resolvedDependencies,
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

    func testResolveDependencies_whenDependencyNameContainsDot_mapsToUnderscoreInTargetName() throws {
        let basePath = try temporaryPath()
        try fileHandler.createFolder(basePath.appending(try RelativePath(validating: "Package/Sources/Target_1")))
        try fileHandler
            .createFolder(basePath.appending(try RelativePath(validating: "com.example.dep-1/Sources/com.example.dep-1")))
        let resolvedDependencies = try subject.resolveExternalDependencies(
            packageInfos: [
                "Package": .init(
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
                "com.example.dep-1": .init(
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
            packageToTargetsToArtifactPaths: [:]
        )

        XCTAssertEqual(
            resolvedDependencies,
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

    func testResolveDependencies_whenTargetDependenciesOnTargetHaveConditions() throws {
        let basePath = try temporaryPath()
        try fileHandler.createFolder(basePath.appending(try RelativePath(validating: "Package/Sources/Target_1")))
        try fileHandler.createFolder(basePath.appending(try RelativePath(validating: "Package/Sources/Dependency_1")))
        try fileHandler.createFolder(basePath.appending(try RelativePath(validating: "Package/Sources/Dependency_2")))
        let resolvedDependencies = try subject.resolveExternalDependencies(
            packageInfos: [
                "Package": .init(
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
            packageToTargetsToArtifactPaths: [:]
        )

        XCTAssertEqual(
            resolvedDependencies,
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

    func testResolveDependencies_whenTargetDependenciesOnProductHaveConditions() throws {
        let basePath = try temporaryPath()
        try fileHandler.createFolder(basePath.appending(try RelativePath(validating: "Package_1/Sources/Target_1")))
        try fileHandler.createFolder(basePath.appending(try RelativePath(validating: "Package_2/Sources/Target_2")))
        try fileHandler.createFolder(basePath.appending(try RelativePath(validating: "Package_2/Sources/Target_3")))
        let resolvedDependencies = try subject.resolveExternalDependencies(
            packageInfos: [
                "Package_1": .init(
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
                "Package_2": .init(
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
            packageToTargetsToArtifactPaths: [:]
        )

        XCTAssertBetterEqual(
            resolvedDependencies,
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

    func testMap() throws {
        let basePath = try temporaryPath()
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try fileHandler.createFolder(sourcesPath)

        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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

        XCTAssertEqual(
            project,
            .testWithDefaultConfigs(
                name: "Package",
                targets: [
                    .test("Target1", basePath: basePath),
                ]
            )
        )
    }

    func testMap_whenLegacySwift_usesLegacyIOSVersion() throws {
        system.swiftVersionStub = { "5.6.0" }

        let basePath = try temporaryPath()
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try fileHandler.createFolder(sourcesPath)

        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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

        XCTAssertBetterEqual(
            project,
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

    func testMap_whenMacCatalyst() throws {
        let basePath = try temporaryPath()
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try fileHandler.createFolder(sourcesPath)

        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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

        XCTAssertBetterEqual(
            project,
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

    func testMap_whenAlternativeDefaultSources() throws {
        for alternativeDefaultSource in ["Source", "src", "srcs"] {
            let basePath = try temporaryPath()
            let sourcesPath = basePath.appending(try RelativePath(validating: "Package/\(alternativeDefaultSource)/Target1"))
            try fileHandler.createFolder(sourcesPath)

            let project = try subject.map(
                package: "Package",
                basePath: basePath,
                packageInfos: [
                    "Package": .init(
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

            XCTAssertBetterEqual(
                project,
                .testWithDefaultConfigs(
                    name: "Package",
                    targets: [
                        .test(
                            "Target1",
                            basePath: basePath,
                            customSources: .custom(.sourceFilesList(
                                globs: [
                                    basePath
                                        .appending(try RelativePath(validating: "Package/\(alternativeDefaultSource)/Target1/**"))
                                        .pathString,
                                ]
                            ))
                        ),
                    ]
                )
            )

            try fileHandler.delete(sourcesPath)
        }
    }

    func testMap_whenOnlyBinaries_doesNotCreateProject() throws {
        let project = try subject.map(
            package: "Package",
            packageInfos: [
                "Package": .init(
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

        XCTAssertNil(project)
    }

    func testMap_whenNameContainsUnderscores_mapsToDashInBundleID() throws {
        let basePath = try temporaryPath()
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target_1"))
        try fileHandler.createFolder(sourcesPath)

        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
        XCTAssertEqual(
            project,
            .testWithDefaultConfigs(
                name: "Package",
                targets: [
                    .test("Target_1", basePath: basePath, customBundleID: "Target.1"),
                ]
            )
        )
    }

    func testMap_whenSettingsDefinesContainsQuotes() throws {
        // When having a manifest that includes a GCC definition like `FOO="BAR"`, SPM successfully maintains the quotes
        // and it will convert it to a compiler parameter like `-DFOO=\"BAR\"`.
        // Xcode configuration, instead, treats the quotes as value assignment, resulting in `-DFOO=BAR`,
        // which has a different meaning in GCC macros, building packages incorrectly.
        // Tuist needs to escape those definitions for SPM manifests, as SPM is doing, so they can be built the same way.

        let basePath = try temporaryPath()
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try fileHandler.createFolder(sourcesPath)

        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
        XCTAssertEqual(
            project,
            .testWithDefaultConfigs(
                name: "Package",
                targets: [
                    .test(
                        "Target1",
                        basePath: basePath,
                        customSettings: [
                            "GCC_PREPROCESSOR_DEFINITIONS": [
                                // Escaped
                                "FOO1='\"BAR1\"'",
                                // Escaped
                                "FOO2='\"BAR2\"'",
                                // Not escaped
                                "FOO3=3",
                            ],
                        ]
                    ),
                ]
            )
        )
    }

    func testMap_whenNameContainsDot_mapsToUnderscoreInTargetName() throws {
        let basePath = try temporaryPath()
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/com.example.target-1"))
        try fileHandler.createFolder(sourcesPath)

        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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

        XCTAssertEqual(
            project,
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
                                .appending(try RelativePath(validating: "Package/Sources/com.example.target-1/**")).pathString,
                        ]))
                    ),
                ]
            )
        )
    }

    func testMap_whenTargetNotInProduct_ignoresIt() throws {
        let basePath = try temporaryPath()
        let sourcesPath1 = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        let sourcesPath2 = basePath.appending(try RelativePath(validating: "Package/Sources/Target2"))
        try fileHandler.createFolder(sourcesPath1)
        try fileHandler.createFolder(sourcesPath2)

        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
        XCTAssertEqual(
            project,
            .testWithDefaultConfigs(
                name: "Package",
                targets: [
                    .test("Target1", basePath: basePath),
                ]
            )
        )
    }

    func testMap_whenTargetIsNotRegular_ignoresTarget() throws {
        let basePath = try temporaryPath()
        let sourcesPath1 = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        let sourcesPath2 = basePath.appending(try RelativePath(validating: "Package/Sources/Target2"))
        let sourcesPath3 = basePath.appending(try RelativePath(validating: "Package/Sources/Target3"))
        try fileHandler.createFolder(sourcesPath1)
        try fileHandler.createFolder(sourcesPath2)
        try fileHandler.createFolder(sourcesPath3)

        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
        XCTAssertEqual(
            project,
            .testWithDefaultConfigs(
                name: "Package",
                targets: [
                    .test("Target1", basePath: basePath),
                ]
            )
        )
    }

    func testMap_whenProductIsNotLibrary_ignoresProduct() throws {
        let basePath = try temporaryPath()
        try fileHandler.createFolder(basePath.appending(try RelativePath(validating: "Package/Sources/Target1")))
        try fileHandler.createFolder(basePath.appending(try RelativePath(validating: "Package/Sources/Target2")))
        try fileHandler.createFolder(basePath.appending(try RelativePath(validating: "Package/Sources/Target3")))

        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
        XCTAssertEqual(
            project,
            .testWithDefaultConfigs(
                name: "Package",
                targets: [
                    .test("Target1", basePath: basePath),
                ]
            )
        )
    }

    func testMap_whenCustomSources() throws {
        let basePath = try temporaryPath()
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try fileHandler.createFolder(sourcesPath)

        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
        XCTAssertEqual(
            project,
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

    func testMap_whenHasResources() throws {
        let basePath = try temporaryPath()
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try fileHandler.createFolder(sourcesPath)

        // Create resources files and directories
        let resource1 = sourcesPath.appending(try RelativePath(validating: "Resource/Folder"))
        let resource2 = sourcesPath.appending(try RelativePath(validating: "Another/Resource/Folder"))
        let resource3 = sourcesPath.appending(try RelativePath(validating: "AnotherOne/Resource/Folder"))

        try fileHandler.createFolder(resource1)
        try fileHandler.createFolder(resource2)
        try fileHandler.createFolder(resource3)

        // Project declaration
        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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

        XCTAssertEqual(
            project,
            .testWithDefaultConfigs(
                name: "Package",
                targets: [
                    .test(
                        "Target1",
                        basePath: basePath,
                        customSources: .custom(.sourceFilesList(globs: [
                            .glob(
                                .path(basePath.appending(try RelativePath(validating: "Package/Sources/Target1/**")).pathString),
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
                                    basePath.appending(try RelativePath(validating: "Package/Sources/Target1/Resource/Folder"))
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
                                            try RelativePath(validating: "Package/Sources/Target1/AnotherOne/Resource/Folder/**")
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

    func testMap_whenHasDefaultResources() throws {
        let basePath = try temporaryPath()
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        let defaultResourcePath = sourcesPath.appending(try RelativePath(validating: "Resources/file.xib"))
        try fileHandler.createFolder(sourcesPath)
        fileHandler.stubFiles = { _, _, _ in
            return [defaultResourcePath]
        }

        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
        XCTAssertEqual(
            project,
            .testWithDefaultConfigs(
                name: "Package",
                targets: [
                    .test(
                        "Target1",
                        basePath: basePath,
                        resources: [
                            .glob(
                                pattern: .path(defaultResourcePath.pathString),
                                excluding: [],
                                tags: []
                            ),
                        ]
                    ),
                ]
            )
        )
    }

    func testMap_whenHasHeadersWithCustomModuleMap() throws {
        let basePath = try temporaryPath()
        let headersPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1/include"))
        let moduleMapPath = headersPath.appending(component: "module.modulemap")
        let topHeaderPath = headersPath.appending(component: "AnHeader.h")
        let nestedHeaderPath = headersPath.appending(component: "Subfolder").appending(component: "AnotherHeader.h")
        try fileHandler.createFolder(headersPath.appending(component: "Subfolder"))
        try fileHandler.write("", path: moduleMapPath, atomically: true)
        try fileHandler.write("", path: topHeaderPath, atomically: true)
        try fileHandler.write("", path: nestedHeaderPath, atomically: true)

        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
        XCTAssertEqual(
            project,
            .testWithDefaultConfigs(
                name: "Package",
                targets: [
                    .test(
                        "Target1",
                        basePath: basePath,
                        customSettings: [
                            "HEADER_SEARCH_PATHS": ["$(SRCROOT)/Sources/Target1/include"],
                            "DEFINES_MODULE": "NO",
                            "OTHER_CFLAGS": .array(["-fmodule-name=Target1"]),
                        ],
                        moduleMap: "$(SRCROOT)/Sources/Target1/include/module.modulemap"
                    ),
                ]
            )
        )
    }

    func testMap_whenHasSystemLibrary() throws {
        let basePath = try temporaryPath()
        let targetPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        let moduleMapPath = targetPath.appending(component: "module.modulemap")
        try fileHandler.createFolder(targetPath)
        try fileHandler.write("", path: moduleMapPath, atomically: true)

        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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

        XCTAssertBetterEqual(
            project,
            .testWithDefaultConfigs(
                name: "Package",
                targets: [
                    .test(
                        "Target1",
                        basePath: basePath,
                        customSources: .custom(nil),
                        customSettings: [
                            "DEFINES_MODULE": "NO",
                            "OTHER_CFLAGS": .array(["-fmodule-name=Target1"]),
                        ],
                        moduleMap: "$(SRCROOT)/Sources/Target1/module.modulemap"
                    ),
                ]
            )
        )
    }

    func testMap_errorWhenSystemLibraryHasMissingModuleMap() throws {
        let basePath = try temporaryPath()
        let targetPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        let moduleMapPath = targetPath.appending(component: "module.modulemap")
        try fileHandler.createFolder(targetPath)

        let error = PackageInfoMapperError.modulemapMissing(
            moduleMapPath: moduleMapPath.pathString,
            package: "Package",
            target: "Target1"
        )

        XCTAssertThrowsSpecific(try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
        ), error)
    }

    func testMap_whenHasHeadersWithUmbrellaHeader() throws {
        let basePath = try temporaryPath()
        let headersPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1/include"))
        let topHeaderPath = headersPath.appending(component: "Target1.h")
        let nestedHeaderPath = headersPath.appending(component: "Subfolder").appending(component: "AnHeader.h")
        try fileHandler.createFolder(headersPath.appending(component: "Subfolder"))
        try fileHandler.write("", path: topHeaderPath, atomically: true)
        try fileHandler.write("", path: nestedHeaderPath, atomically: true)

        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
        XCTAssertBetterEqual(
            project,
            .testWithDefaultConfigs(
                name: "Package",
                targets: [
                    .test(
                        "Target1",
                        basePath: basePath,
                        customSettings: [
                            "HEADER_SEARCH_PATHS": ["$(SRCROOT)/Sources/Target1/include"],
                            "MODULEMAP_FILE": .string("$(SRCROOT)/Derived/Target1.modulemap"),
                            "DEFINES_MODULE": "NO",
                            "OTHER_CFLAGS": .array(["-fmodule-name=Target1"]),
                        ]
                    ),
                ]
            )
        )
    }

    func testMap_whenDependenciesHaveHeaders() throws {
        let basePath = try temporaryPath()
        let target1HeadersPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1/include"))
        let target1ModuleMapPath = target1HeadersPath.appending(component: "module.modulemap")
        let dependency1HeadersPath = basePath.appending(try RelativePath(validating: "Package/Sources/Dependency1/include"))
        let dependency1ModuleMapPath = dependency1HeadersPath.appending(component: "module.modulemap")
        let dependency2HeadersPath = basePath.appending(try RelativePath(validating: "Package/Sources/Dependency2/include"))
        let dependency2ModuleMapPath = dependency2HeadersPath.appending(component: "module.modulemap")
        try fileHandler.createFolder(target1HeadersPath.appending(component: "Subfolder"))
        try fileHandler.write("", path: target1ModuleMapPath, atomically: true)
        try fileHandler.createFolder(dependency1HeadersPath.appending(component: "Subfolder"))
        try fileHandler.write("", path: dependency1ModuleMapPath, atomically: true)
        try fileHandler.createFolder(dependency2HeadersPath.appending(component: "Subfolder"))
        try fileHandler.write("", path: dependency2ModuleMapPath, atomically: true)

        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
        XCTAssertBetterEqual(
            project,
            .testWithDefaultConfigs(
                name: "Package",
                targets: [
                    .test(
                        "Target1",
                        basePath: basePath,
                        dependencies: [.target(name: "Dependency1")],
                        customSettings: [
                            "HEADER_SEARCH_PATHS": [
                                "$(SRCROOT)/Sources/Target1/include",
                            ],
                            "DEFINES_MODULE": "NO",
                            "OTHER_CFLAGS": .array(["-fmodule-name=Target1"]),
                        ],
                        moduleMap: "$(SRCROOT)/Sources/Target1/include/module.modulemap"
                    ),
                    .test(
                        "Dependency1",
                        basePath: basePath,
                        dependencies: [.target(name: "Dependency2")],
                        customSettings: [
                            "HEADER_SEARCH_PATHS": [
                                "$(SRCROOT)/Sources/Dependency1/include",
                            ],
                            "DEFINES_MODULE": "NO",
                            "OTHER_CFLAGS": .array(["-fmodule-name=Dependency1"]),
                        ],
                        moduleMap: "$(SRCROOT)/Sources/Dependency1/include/module.modulemap"
                    ),
                    .test(
                        "Dependency2",
                        basePath: basePath,
                        customSettings: [
                            "HEADER_SEARCH_PATHS": [
                                "$(SRCROOT)/Sources/Dependency2/include",
                            ],
                            "DEFINES_MODULE": "NO",
                            "OTHER_CFLAGS": .array(["-fmodule-name=Dependency2"]),
                        ],
                        moduleMap: "$(SRCROOT)/Sources/Dependency2/include/module.modulemap"
                    ),
                ]
            )
        )
    }

    func testMap_whenExternalDependenciesHaveHeaders() throws {
        let basePath = try temporaryPath()
        let target1HeadersPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1/include"))
        let target1ModuleMapPath = target1HeadersPath.appending(component: "module.modulemap")
        let dependency1HeadersPath = basePath.appending(try RelativePath(validating: "Package2/Sources/Dependency1/include"))
        let dependency1ModuleMapPath = dependency1HeadersPath.appending(component: "module.modulemap")
        let dependency2HeadersPath = basePath.appending(try RelativePath(validating: "Package3/Sources/Dependency2/include"))
        let dependency2ModuleMapPath = dependency2HeadersPath.appending(component: "module.modulemap")
        try fileHandler.createFolder(target1HeadersPath.appending(component: "Subfolder"))
        try fileHandler.write("", path: target1ModuleMapPath, atomically: true)
        try fileHandler.createFolder(dependency1HeadersPath.appending(component: "Subfolder"))
        try fileHandler.write("", path: dependency1ModuleMapPath, atomically: true)
        try fileHandler.createFolder(dependency2HeadersPath.appending(component: "Subfolder"))
        try fileHandler.write("", path: dependency2ModuleMapPath, atomically: true)

        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
                "Package2": .init(
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
                "Package3": .init(
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
        XCTAssertBetterEqual(
            project,
            .testWithDefaultConfigs(
                name: "Package",
                targets: [
                    .test(
                        "Target1",
                        basePath: basePath,
                        dependencies: [.external(name: "Dependency1", condition: nil)],
                        customSettings: [
                            "HEADER_SEARCH_PATHS": [
                                "$(SRCROOT)/Sources/Target1/include",
                            ],
                            "DEFINES_MODULE": "NO",
                            "OTHER_CFLAGS": .array(["-fmodule-name=Target1"]),
                        ],
                        moduleMap: "$(SRCROOT)/Sources/Target1/include/module.modulemap"
                    ),
                ]
            )
        )
    }

    func testMap_whenCustomPath() throws {
        let basePath = try temporaryPath()

        // Create resources files and directories
        let headersPath = basePath.appending(try RelativePath(validating: "Package/Custom/Headers"))
        let headerPath = headersPath.appending(component: "module.h")
        let moduleMapPath = headersPath.appending(component: "module.modulemap")
        try fileHandler.createFolder(headersPath)
        try fileHandler.write("", path: headerPath, atomically: true)
        try fileHandler.write("", path: moduleMapPath, atomically: true)

        let resourceFolderPathCustomTarget = basePath.appending(try RelativePath(validating: "Package/Custom/Resource/Folder"))
        try fileHandler.createFolder(resourceFolderPathCustomTarget)

        // Project declaration
        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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

        XCTAssertEqual(
            project,
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
                            "HEADER_SEARCH_PATHS": ["$(SRCROOT)/Custom/Headers"],
                            "DEFINES_MODULE": "NO",
                            "OTHER_CFLAGS": .array(["-fmodule-name=Target1"]),
                        ],
                        moduleMap: "$(SRCROOT)/Custom/Headers/module.modulemap"
                    ),
                ]
            )
        )
    }

    func testMap_whenDependencyHasHeaders_addsThemToHeaderSearchPath() throws {
        let basePath = try temporaryPath()
        let dependencyHeadersPath = basePath.appending(try RelativePath(validating: "Package/Sources/Dependency1/include"))
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try fileHandler.createFolder(dependencyHeadersPath)
        try fileHandler.createFolder(sourcesPath)
        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
        XCTAssertBetterEqual(
            project,
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
                            "HEADER_SEARCH_PATHS": ["$(SRCROOT)/Sources/Dependency1/include"],
                            "DEFINES_MODULE": "NO",
                            "OTHER_CFLAGS": .array(["-fmodule-name=Dependency1"]),
                        ],
                        moduleMap: "$(SRCROOT)/Derived/Dependency1.modulemap"
                    ),
                ]
            )
        )
    }

    func testMap_whenMultipleAvailable_takesMultiple() throws {
        // Given
        let basePath = try temporaryPath()
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try fileHandler.createFolder(sourcesPath)

        // When
        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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

        XCTAssertEqual(project?.name, expected.name)

        // Need to sort targets of projects, because internally a set is used to generate targets for different platforms
        // That could lead to mixed orders
        let projectTargets = project?.targets.sorted(by: \.name)
        let expectedTargets = expected.targets.sorted(by: \.name)
        XCTAssertBetterEqual(projectTargets, expectedTargets)
    }

    func testMap_whenPackageDefinesPlatform_configuresDeploymentTarget() throws {
        let basePath = try temporaryPath()
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try fileHandler.createFolder(sourcesPath)
        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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

        XCTAssertBetterEqual(
            project,
            other
        )
    }

    func testMap_whenSettingsContainsCHeaderSearchPath_mapsToHeaderSearchPathsSetting() throws {
        let basePath = try temporaryPath()
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try fileHandler.createFolder(sourcesPath)
        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
                    name: "Package",
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1",
                            settings: [.init(tool: .c, name: .headerSearchPath, condition: nil, value: ["value"])]
                        ),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        XCTAssertEqual(
            project,
            .testWithDefaultConfigs(
                name: "Package",
                targets: [
                    .test(
                        "Target1",
                        basePath: basePath,
                        customSettings: ["HEADER_SEARCH_PATHS": ["$(SRCROOT)/Sources/Target1/value"]]
                    ),
                ]
            )
        )
    }

    func testMap_whenSettingsContainsCXXHeaderSearchPath_mapsToHeaderSearchPathsSetting() throws {
        let basePath = try temporaryPath()
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try fileHandler.createFolder(sourcesPath)
        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
        XCTAssertEqual(
            project,
            .testWithDefaultConfigs(
                name: "Package",
                targets: [
                    .test(
                        "Target1",
                        basePath: basePath,
                        customSettings: ["HEADER_SEARCH_PATHS": ["$(SRCROOT)/Sources/Target1/value"]]
                    ),
                ]
            )
        )
    }

    func testMap_whenSettingsContainsCDefine_mapsToGccPreprocessorDefinitions() throws {
        let basePath = try temporaryPath()
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try fileHandler.createFolder(sourcesPath)
        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
        XCTAssertEqual(
            project,
            .testWithDefaultConfigs(
                name: "Package",
                targets: [
                    .test(
                        "Target1",
                        basePath: basePath,
                        customSettings: ["GCC_PREPROCESSOR_DEFINITIONS": ["key1=1", "key2=value", "key3="]]
                    ),
                ]
            )
        )
    }

    func testMap_whenSettingsContainsCXXDefine_mapsToGccPreprocessorDefinitions() throws {
        let basePath = try temporaryPath()
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try fileHandler.createFolder(sourcesPath)
        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
        XCTAssertEqual(
            project,
            .testWithDefaultConfigs(
                name: "Package",
                targets: [
                    .test(
                        "Target1",
                        basePath: basePath,
                        customSettings: ["GCC_PREPROCESSOR_DEFINITIONS": ["key1=1", "key2=value"]]
                    ),
                ]
            )
        )
    }

    func testMap_whenSettingsContainsSwiftDefine_mapsToSwiftActiveCompilationConditions() throws {
        let basePath = try temporaryPath()
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try fileHandler.createFolder(sourcesPath)
        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
        XCTAssertEqual(
            project,
            .testWithDefaultConfigs(
                name: "Package",
                targets: [
                    .test("Target1", basePath: basePath, customSettings: ["SWIFT_ACTIVE_COMPILATION_CONDITIONS": "key"]),
                ]
            )
        )
    }

    func testMap_whenSettingsContainsCUnsafeFlags_mapsToOtherCFlags() throws {
        let basePath = try temporaryPath()
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try fileHandler.createFolder(sourcesPath)
        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
        XCTAssertEqual(
            project,
            .testWithDefaultConfigs(
                name: "Package",
                targets: [
                    .test("Target1", basePath: basePath, customSettings: ["OTHER_CFLAGS": ["key1", "key2", "key3"]]),
                ]
            )
        )
    }

    func testMap_whenSettingsContainsCXXUnsafeFlags_mapsToOtherCPlusPlusFlags() throws {
        let basePath = try temporaryPath()
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try fileHandler.createFolder(sourcesPath)
        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
        XCTAssertEqual(
            project,
            .testWithDefaultConfigs(
                name: "Package",
                targets: [
                    .test("Target1", basePath: basePath, customSettings: ["OTHER_CPLUSPLUSFLAGS": ["key1", "key2", "key3"]]),
                ]
            )
        )
    }

    func testMap_whenSettingsContainsSwiftUnsafeFlags_mapsToOtherSwiftFlags() throws {
        let basePath = try temporaryPath()
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try fileHandler.createFolder(sourcesPath)
        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
        XCTAssertEqual(
            project,
            .testWithDefaultConfigs(
                name: "Package",
                targets: [
                    .test("Target1", basePath: basePath, customSettings: ["OTHER_SWIFT_FLAGS": ["key1", "key2", "key3"]]),
                ]
            )
        )
    }

    func testMap_whenSettingsContainsEnableUpcomingFeature_mapsToOtherSwiftFlags() throws {
        let basePath = try temporaryPath()
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try fileHandler.createFolder(sourcesPath)
        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
        XCTAssertEqual(
            project,
            .testWithDefaultConfigs(
                name: "Package",
                targets: [
                    .test("Target1", basePath: basePath, customSettings: ["OTHER_SWIFT_FLAGS": ["-enable-upcoming-feature Foo"]]),
                ]
            )
        )
    }

    func testMap_whenSettingsContainsEnableExperimentalFeature_mapsToOtherSwiftFlags() throws {
        let basePath = try temporaryPath()
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try fileHandler.createFolder(sourcesPath)
        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
        XCTAssertEqual(
            project,
            .testWithDefaultConfigs(
                name: "Package",
                targets: [
                    .test(
                        "Target1",
                        basePath: basePath,
                        customSettings: ["OTHER_SWIFT_FLAGS": ["-enable-experimental-feature Foo"]]
                    ),
                ]
            )
        )
    }

    func testMap_whenSettingsContainsLinkerUnsafeFlags_mapsToOtherLdFlags() throws {
        let basePath = try temporaryPath()
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try fileHandler.createFolder(sourcesPath)

        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
        XCTAssertEqual(
            project,
            .testWithDefaultConfigs(
                name: "Package",
                targets: [
                    .test("Target1", basePath: basePath, customSettings: ["OTHER_LDFLAGS": ["key1", "key2", "key3"]]),
                ]
            )
        )
    }

    func testMap_whenConfigurationContainsBaseSettingsDictionary_usesBaseSettings() throws {
        let basePath = try temporaryPath()
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try fileHandler.createFolder(sourcesPath)

        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
                baseSettings: .init(
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
        XCTAssertEqual(
            project,
            .testWithDefaultConfigs(
                name: "Package",
                targets: [
                    .test(
                        "Target1",
                        basePath: basePath,
                        baseSettings: .settings(
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
                        customSettings: [
                            "OTHER_LDFLAGS": ["key1", "key2", "key3"],
                        ]
                    ),
                ]
            )
        )
    }

    func testMap_whenConfigurationContainsTargetSettingsDictionary_mapsToCustomSettings() throws {
        let basePath = try temporaryPath()
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try fileHandler.createFolder(sourcesPath)

        let customSettings: TuistGraph.SettingsDictionary = ["CUSTOM_SETTING": .string("CUSTOM_VALUE")]

        let targetSettings = ["Target1": customSettings]

        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
        XCTAssertEqual(
            project,
            .testWithDefaultConfigs(
                name: "Package",
                targets: [
                    .test(
                        "Target1",
                        basePath: basePath,
                        customSettings: [
                            "OTHER_LDFLAGS": ["key1", "key2", "key3"],
                            "CUSTOM_SETTING": "CUSTOM_VALUE",
                        ]
                    ),
                ]
            )
        )
    }

    func testMap_whenConditionalSetting_ignoresByPlatform() throws {
        let basePath = try temporaryPath()
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try fileHandler.createFolder(sourcesPath)

        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
        XCTAssertEqual(
            project,
            .testWithDefaultConfigs(
                name: "Package",
                targets: [
                    .test(
                        "Target1",
                        basePath: basePath,
                        customSettings: ["HEADER_SEARCH_PATHS": ["$(SRCROOT)/Sources/Target1/otherValue"]]
                    ),
                ]
            )
        )
    }

    func testMap_whenSettingsContainsLinkedFramework_mapsToSDKDependency() throws {
        let basePath = try temporaryPath()
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try fileHandler.createFolder(sourcesPath)

        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
        XCTAssertEqual(
            project,
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

    func testMap_whenSettingsContainsLinkedLibrary_mapsToSDKDependency() throws {
        let basePath = try temporaryPath()
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try fileHandler.createFolder(sourcesPath)

        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
        XCTAssertEqual(
            project,
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

    func testMap_whenTargetDependency_mapsToTargetDependency() throws {
        let basePath = try temporaryPath()
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        let dependenciesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Dependency1"))
        try fileHandler.createFolder(sourcesPath)
        try fileHandler.createFolder(dependenciesPath)

        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
        XCTAssertEqual(
            project,
            .testWithDefaultConfigs(
                name: "Package",
                targets: [
                    .test("Target1", basePath: basePath, dependencies: [.target(name: "Dependency1")]),
                    .test("Dependency1", basePath: basePath),
                ]
            )
        )
    }

    func testMap_whenBinaryTargetDependency_mapsToXcframework() throws {
        let basePath = try temporaryPath()
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        let dependenciesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Dependency1"))
        try fileHandler.createFolder(sourcesPath)
        try fileHandler.createFolder(dependenciesPath)

        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
        XCTAssertEqual(
            project,
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

    func testMap_whenTargetByNameDependency_mapsToTargetDependency() throws {
        let basePath = try temporaryPath()
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        let dependenciesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Dependency1"))
        try fileHandler.createFolder(sourcesPath)
        try fileHandler.createFolder(dependenciesPath)

        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
        XCTAssertEqual(
            project,
            .testWithDefaultConfigs(
                name: "Package",
                targets: [
                    .test("Target1", basePath: basePath, dependencies: [.target(name: "Dependency1")]),
                    .test("Dependency1", basePath: basePath),
                ]
            )
        )
    }

    func testMap_whenBinaryTargetURLByNameDependency_mapsToXcFramework() throws {
        let basePath = try temporaryPath()
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try fileHandler.createFolder(sourcesPath)

        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
        XCTAssertEqual(
            project,
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

    func testMap_whenBinaryTargetPathByNameDependency_mapsToXcFramework() throws {
        let basePath = try temporaryPath()
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try fileHandler.createFolder(sourcesPath)

        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
                        .test(name: "Dependency1", type: .binary, path: "Dependency1/Dependency1.xcframework"),
                    ],
                    platforms: [.ios],
                    cLanguageStandard: nil,
                    cxxLanguageStandard: nil,
                    swiftLanguageVersions: nil
                ),
            ]
        )
        XCTAssertBetterEqual(
            project,
            .testWithDefaultConfigs(
                name: "Package",
                targets: [
                    .test(
                        "Target1",
                        basePath: basePath,
                        dependencies: [.xcframework(path: .path(
                            basePath
                                .appending(try RelativePath(validating: "artifacts/Package/Dependency1/Dependency1.xcframework"))
                                .pathString
                        ))]
                    ),
                ]
            )
        )
    }

    func testMap_whenExternalProductDependency_mapsToProjectDependencies() throws {
        let basePath = try temporaryPath()
        try fileHandler.createFolder(basePath.appending(try RelativePath(validating: "Package/Sources/Target1")))
        try fileHandler.createFolder(basePath.appending(try RelativePath(validating: "Package2/Sources/Target2")))
        try fileHandler.createFolder(basePath.appending(try RelativePath(validating: "Package2/Sources/Target3")))
        try fileHandler.createFolder(basePath.appending(try RelativePath(validating: "Package2/Sources/Target4")))
        try fileHandler.createFolder(basePath.appending(try RelativePath(validating: "Package/Sources/Dependency1")))

        let package1 = PackageInfo(
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
        let package2 = PackageInfo(
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
        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: ["Package": package1, "Package2": package2]
        )
        XCTAssertBetterEqual(
            project,
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

    func testMap_whenExternalByNameProductDependency_mapsToProjectDependencies() throws {
        let basePath = try temporaryPath()
        try fileHandler.createFolder(basePath.appending(try RelativePath(validating: "Package/Sources/Target1")))
        try fileHandler.createFolder(basePath.appending(try RelativePath(validating: "Package2/Sources/Target2")))
        try fileHandler.createFolder(basePath.appending(try RelativePath(validating: "Package2/Sources/Target3")))
        try fileHandler.createFolder(basePath.appending(try RelativePath(validating: "Package2/Sources/Target4")))
        try fileHandler.createFolder(basePath.appending(try RelativePath(validating: "Package/Sources/Dependency1")))

        let package1 = PackageInfo(
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
        let package2 = PackageInfo(
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
        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: ["Package": package1, "Package2": package2]
        )
        XCTAssertBetterEqual(
            project,
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

    func testMap_whenCustomCVersion_mapsToGccCLanguageStandardSetting() throws {
        let basePath = try temporaryPath()
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try fileHandler.createFolder(sourcesPath)

        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                settings: .settings(base: ["GCC_C_LANGUAGE_STANDARD": "c99"]),
                targets: [
                    .test("Target1", basePath: basePath),
                ]
            )
        )
    }

    func testMap_whenCustomCXXVersion_mapsToClangCxxLanguageStandardSetting() throws {
        let basePath = try temporaryPath()
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try fileHandler.createFolder(sourcesPath)

        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                settings: .settings(base: ["CLANG_CXX_LANGUAGE_STANDARD": "gnu++14"]),
                targets: [
                    .test("Target1", basePath: basePath),
                ]
            )
        )
    }

    func testMap_whenCustomSwiftVersion_mapsToSwiftVersionSetting() throws {
        let basePath = try temporaryPath()
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try fileHandler.createFolder(sourcesPath)

        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                settings: .settings(base: ["SWIFT_VERSION": "4.0.0"]),
                targets: [
                    .test("Target1", basePath: basePath),
                ]
            )
        )
    }

    func testMap_whenMultipleCustomSwiftVersions_mapsLargestToSwiftVersionSetting() throws {
        let basePath = try temporaryPath()
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try fileHandler.createFolder(sourcesPath)

        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                settings: .settings(base: ["SWIFT_VERSION": "5.0.0"]),
                targets: [
                    .test("Target1", basePath: basePath),
                ]
            )
        )
    }

    func testMap_whenMultipleCustomSwiftVersionsAndConfiguredVersion_mapsLargestToSwiftVersionLowerThanConfigured() throws {
        let basePath = try temporaryPath()
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try fileHandler.createFolder(sourcesPath)

        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
            ],
            packageSettings: .test(
                baseSettings: .default,
                swiftToolsVersion: "4.4.0"
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                settings: .settings(base: ["SWIFT_VERSION": "4.2.0"]),
                targets: [
                    .test("Target1", basePath: basePath),
                ]
            )
        )
    }

    func testMap_whenDependenciesContainsCustomConfiguration_mapsToProjectWithCustomConfig() throws {
        let basePath = try temporaryPath()
        let sourcesPath = basePath.appending(try RelativePath(validating: "Package/Sources/Target1"))
        try fileHandler.createFolder(sourcesPath)

        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
                ),
                swiftToolsVersion: "4.4.0"
            )
        )

        XCTAssertNotNil(project?.settings?.configurations.first(where: { $0.name == "Custom" }))
    }

    func testMap_whenTargetsWithDefaultHardcodedMapping() throws {
        let basePath = try temporaryPath()
        let testTargets = [
            "Nimble",
            "Quick",
            "RxTest",
            "RxTest-Dynamic",
            "SnapshotTesting",
            "TempuraTesting",
            "TSCTestSupport",
            "ViewInspector",
            "XCTVapor",
        ]
        let allTargets = ["RxSwift"] + testTargets
        try allTargets
            .map { basePath.appending(try RelativePath(validating: "Package/Sources/\($0)")) }
            .forEach { try fileHandler.createFolder($0) }

        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
                    "Nimble": ["ENABLE_TESTING_SEARCH_PATHS": "NO", "ANOTHER_SETTING": "YES"],
                    "Quick": ["ANOTHER_SETTING": "YES"],
                ]
            )
        )

        XCTAssertEqual(
            project,
            .testWithDefaultConfigs(
                name: "Package",
                targets: [
                    .test("RxSwift", basePath: basePath, product: .framework),
                ] + testTargets.map {
                    let customSettings: ProjectDescription.SettingsDictionary
                    var customProductName: String?
                    switch $0 {
                    case "Nimble":
                        customSettings = ["ENABLE_TESTING_SEARCH_PATHS": "NO", "ANOTHER_SETTING": "YES"]
                    case "Quick":
                        customSettings = ["ENABLE_TESTING_SEARCH_PATHS": "YES", "ANOTHER_SETTING": "YES"]
                    case "RxTest-Dynamic": // because RxTest does have an "-" we need to account for the custom mapping to product
                        // names
                        customProductName = "RxTest_Dynamic"
                        customSettings = ["ENABLE_TESTING_SEARCH_PATHS": "YES"]
                    default:
                        customSettings = ["ENABLE_TESTING_SEARCH_PATHS": "YES"]
                    }

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

    func testMap_whenTargetDependenciesOnTargetHaveConditions() throws {
        let basePath = try temporaryPath()
        try fileHandler.createFolder(basePath.appending(try RelativePath(validating: "Package/Sources/Target1")))
        try fileHandler.createFolder(basePath.appending(try RelativePath(validating: "Package/Sources/Dependency1")))
        try fileHandler.createFolder(basePath.appending(try RelativePath(validating: "Package/Sources/Dependency2")))

        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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

        XCTAssertEqual(project?.name, expected.name)

        let projectTargets = project!.targets.sorted(by: \.name)
        let expectedTargets = expected.targets.sorted(by: \.name)
        XCTAssertBetterEqual(projectTargets, expectedTargets)
    }

    func testMap_whenTargetDependenciesOnProductHaveConditions() throws {
        let basePath = try temporaryPath()
        try fileHandler.createFolder(basePath.appending(try RelativePath(validating: "Package/Sources/Target1")))
        try fileHandler.createFolder(basePath.appending(try RelativePath(validating: "Package2/Sources/Target2")))
        try fileHandler.createFolder(basePath.appending(try RelativePath(validating: "Package2/Sources/Target3")))

        let package1 = PackageInfo(
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
        let package2 = PackageInfo(
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
        let project = try subject.map(
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

        XCTAssertEqual(project?.name, expected.name)

        let projectTargets = project!.targets.sorted(by: \.name)
        let expectedTargets = expected.targets.sorted(by: \.name)

        XCTAssertBetterEqual(
            projectTargets,
            expectedTargets
        )
    }
}

private func defaultSpmResources(_ target: String, customPath: String? = nil) -> ResourceFileElements {
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
        packageInfos: [String: PackageInfo] = [:],
        packageSettings: TuistGraph.PackageSettings = .test(
            baseSettings: .default
        )
    ) throws -> ProjectDescription.Project? {
        let packageToTargetsToArtifactPaths: [String: [String: AbsolutePath]] = try packageInfos
            .reduce(into: [:]) { packagesResult, element in
                let (packageName, packageInfo) = element
                packagesResult[packageName] = try packageInfo.targets
                    .reduce(into: [String: AbsolutePath]()) { targetsResult, target in
                        guard target.type == .binary else {
                            return
                        }
                        if let path = target.path {
                            targetsResult[target.name] = basePath.appending(
                                try RelativePath(validating: "artifacts/\(packageName)/\(path)")
                            )
                        } else {
                            targetsResult[target.name] = basePath.appending(
                                try RelativePath(validating: "artifacts/\(packageName)/\(target.name).xcframework")
                            )
                        }
                    }
            }

        return try map(
            packageInfo: packageInfos[package]!,
            path: basePath.appending(component: package),
            packageType: .external(artifactPaths: packageToTargetsToArtifactPaths[package]!),
            packageSettings: packageSettings,
            packageToProject: Dictionary(uniqueKeysWithValues: packageInfos.keys.map {
                ($0, basePath.appending(component: $0))
            })
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
        settings: ProjectDescription.Settings? = nil,
        targets: [ProjectDescription.Target]
    ) -> Self {
        .init(
            name: name,
            options: .options(
                automaticSchemesOptions: .disabled,
                disableBundleAccessors: false,
                disableSynthesizedResourceAccessors: true,
                textSettings: .textSettings(usesTabs: nil, indentWidth: nil, tabWidth: nil, wrapsLines: nil)
            ),
            settings: settings,
            targets: targets,
            resourceSynthesizers: .default
        )
    }

    fileprivate static func testWithDefaultConfigs(
        name: String,
        targets: [ProjectDescription.Target]
    ) -> Self {
        Project.test(
            name: name,
            settings: .settings(configurations: [
                .debug(name: .debug),
                .release(name: .release),
            ]),
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
        customSettings: ProjectDescription.SettingsDictionary = [:],
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
                    basePath.appending(try! RelativePath(validating: "Package/Sources/\(name)/**"))
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
            settings: DependenciesGraph.spmSettings(
                packageName: packageName,
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
