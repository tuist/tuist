import ProjectDescription
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistDependencies
@testable import TuistDependenciesTesting
@testable import TuistSupportTesting

final class PackageInfoMapperTests: TuistUnitTestCase {
    private var subject: PackageInfoMapper!

    override func setUp() {
        super.setUp()

        subject = PackageInfoMapper()

        // FileHandler
        fileHandler = MockFileHandler(temporaryDirectory: { try self.temporaryPath() })
        FileHandler.shared = fileHandler
    }

    override func tearDown() {
        subject = nil

        super.tearDown()
    }

    func testMap() throws {
        let project = try subject.map(
            packageInfo: .init(
                products: [
                    .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                ],
                targets: [
                    .test(name: "Target1"),
                ],
                platforms: []
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test("Target1"),
                ]
            )
        )
    }

    func testMap_whenNameContainsUnderscors_mapsToDashInBundleID() throws {
        let project = try subject.map(
            packageInfo: .init(
                products: [
                    .init(name: "Product1", type: .library(.automatic), targets: ["Target_1"]),
                ],
                targets: [
                    .test(name: "Target_1"),
                ],
                platforms: []
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test("Target_1", customBundleID: "Target-1"),
                ]
            )
        )
    }

    func testMap_whenTargetNotInProduct_ignoresIt() throws {
        let project = try subject.map(
            packageInfo: .init(
                products: [
                    .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                ],
                targets: [
                    .test(name: "Target1"),
                    .test(name: "Target2"),
                ],
                platforms: []
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test("Target1"),
                ]
            )
        )
    }

    func testMap_whenTargetIsNotRegular_ignoresTarget() throws {
        let project = try subject.map(
            packageInfo: .init(
                products: [
                    .init(name: "Product1", type: .library(.automatic), targets: ["Target1", "Target2", "Target3"]),
                ],
                targets: [
                    .test(name: "Target1"),
                    .test(name: "Target2", type: .test),
                    .test(name: "Target3", type: .binary),
                ],
                platforms: []
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test("Target1"),
                ]
            )
        )
    }

    func testMap_whenProductIsNotLibrary_ignoresProduct() throws {
        let project = try subject.map(
            packageInfo: .init(
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
                platforms: []
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test("Target1"),
                ]
            )
        )
    }

    func testMap_whenCustomSources() throws {
        let project = try subject.map(
            packageInfo: .init(
                products: [
                    .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                ],
                targets: [
                    .test(name: "Target1", sources: ["Subfolder", "Another/Subfolder/file.swift"]),
                ],
                platforms: []
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test(
                        "Target1",
                        customSources: [
                            "/Package/Path/Sources/Target1/Subfolder/**",
                            "/Package/Path/Sources/Target1/Another/Subfolder/file.swift",
                        ]
                    ),
                ]
            )
        )
    }

    func testMap_whenHasResources() throws {
        let project = try subject.map(
            packageInfo: .init(
                products: [
                    .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                ],
                targets: [
                    .test(
                        name: "Target1",
                        resources: [
                            .init(rule: .copy, path: "Resource/Folder"),
                            .init(rule: .process, path: "Another/Resource/Folder"),
                        ]
                    ),
                ],
                platforms: []
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test(
                        "Target1",
                        resources: [
                            "/Package/Path/Sources/Target1/Resource/Folder/**",
                            "/Package/Path/Sources/Target1/Another/Resource/Folder/**",
                        ]
                    ),
                ]
            )
        )
    }

    func testMap_whenHasHeaders() throws {
        fileHandler.stubContentsOfDirectory = { path in
            XCTAssertEqual(path, "/Package/Path/Sources/Target1/include")
            return [
                "/Package/Path/Sources/Target1/include/Public.h",
                "/Package/Path/Sources/Target1/include/Others.swift",
            ]
        }
        let project = try subject.map(
            packageInfo: .init(
                products: [
                    .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                ],
                targets: [
                    .test(
                        name: "Target1"
                    ),
                ],
                platforms: []
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test(
                        "Target1",
                        headers: .init(public: "/Package/Path/Sources/Target1/include/Public.h")
                    ),
                ]
            )
        )
    }

    func testMap_whenCustomPath() throws {
        fileHandler.stubContentsOfDirectory = { path in
            XCTAssertEqual(path, "/Package/Path/Custom/Path/Headers")
            return [
                "/Package/Path/Custom/Path/Headers/Source.h",
            ]
        }
        let project = try subject.map(
            packageInfo: .init(
                products: [
                    .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                ],
                targets: [
                    .test(
                        name: "Target1",
                        path: "Custom/Path",
                        sources: ["Sources/Folder"],
                        resources: [.init(rule: .copy, path: "Resource/Folder")],
                        publicHeadersPath: "Headers"
                    ),
                ],
                platforms: []
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test(
                        "Target1",
                        customSources: "/Package/Path/Custom/Path/Sources/Folder/**",
                        resources: "/Package/Path/Custom/Path/Resource/Folder/**",
                        headers: .init(public: "/Package/Path/Custom/Path/Headers/Source.h")
                    ),
                ]
            )
        )
    }

    func testMap_whenIOSAvailable_takesIOS() throws {
        let project = try subject.map(
            packageInfo: .init(
                products: [
                    .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                ],
                targets: [
                    .test(name: "Target1"),
                ],
                platforms: []
            ),
            platforms: [.iOS, .tvOS]
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test("Target1", platform: .iOS),
                ]
            )
        )
    }

    func testMap_whenIOSNotAvailable_takesOthers() throws {
        let project = try subject.map(
            packageInfo: .init(
                products: [
                    .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                ],
                targets: [
                    .test(name: "Target1"),
                ],
                platforms: []
            ),
            platforms: [.tvOS]
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test("Target1", platform: .tvOS),
                ]
            )
        )
    }

    func testMap_whenNoneAvailable_throws() throws {
        XCTAssertThrowsSpecific(
            try subject.map(
                packageInfo: .init(
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(name: "Target1"),
                    ],
                    platforms: [.init(platformName: "tvos", version: "13.0", options: [])]
                ),
                platforms: [.iOS]
            ),
            PackageInfoMapperError.noSupportedPlatforms(
                name: "Package",
                configured: [.iOS],
                package: [.tvOS]
            )
        )
    }

    func testMap_whenPackageDefinesPlatform_configuresDeploymentTarget() throws {
        let project = try subject.map(
            packageInfo: .init(
                products: [
                    .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                ],
                targets: [
                    .test(name: "Target1"),
                ],
                platforms: [.init(platformName: "ios", version: "13.0", options: [])]
            ),
            platforms: [.iOS]
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test("Target1", platform: .iOS, deploymentTarget: .iOS(targetVersion: "13.0", devices: [.iphone, .ipad, .mac])),
                ]
            )
        )
    }

    func testMap_whenSettingsContainsCHeaderSearchPath_mapsToHeaderSearchPathsSetting() throws {
        let project = try subject.map(
            packageInfo: .init(
                products: [
                    .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                ],
                targets: [
                    .test(
                        name: "Target1",
                        settings: [.init(tool: .c, name: .headerSearchPath, condition: nil, value: ["value"])]
                    ),
                ],
                platforms: []
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test("Target1", customSettings: ["HEADER_SEARCH_PATHS": ["/Package/Path/Sources/Target1/value"]]),
                ]
            )
        )
    }

    func testMap_whenSettingsContainsCXXHeaderSearchPath_mapsToHeaderSearchPathsSetting() throws {
        let project = try subject.map(
            packageInfo: .init(
                products: [
                    .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                ],
                targets: [
                    .test(
                        name: "Target1",
                        settings: [.init(tool: .cxx, name: .headerSearchPath, condition: nil, value: ["value"])]
                    ),
                ],
                platforms: []
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test("Target1", customSettings: ["HEADER_SEARCH_PATHS": ["/Package/Path/Sources/Target1/value"]]),
                ]
            )
        )
    }

    func testMap_whenSettingsContainsCDefine_mapsToGccPreprocessorDefinitions() throws {
        let project = try subject.map(
            packageInfo: .init(
                products: [
                    .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                ],
                targets: [
                    .test(
                        name: "Target1",
                        settings: [
                            .init(tool: .c, name: .define, condition: nil, value: ["key1"]),
                            .init(tool: .c, name: .define, condition: nil, value: ["key2=value"]),
                        ]
                    ),
                ],
                platforms: []
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test("Target1", customSettings: ["GCC_PREPROCESSOR_DEFINITIONS": ["key1=1", "key2=value"]]),
                ]
            )
        )
    }

    func testMap_whenSettingsContainsCXXDefine_mapsToGccPreprocessorDefinitions() throws {
        let project = try subject.map(
            packageInfo: .init(
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
                platforms: []
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test("Target1", customSettings: ["GCC_PREPROCESSOR_DEFINITIONS": ["key1=1", "key2=value"]]),
                ]
            )
        )
    }

    func testMap_whenSettingsContainsSwiftDefine_mapsToSwiftActiveCompilationConditions() throws {
        let project = try subject.map(
            packageInfo: .init(
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
                platforms: []
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test("Target1", customSettings: ["SWIFT_ACTIVE_COMPILATION_CONDITIONS": ["key"]]),
                ]
            )
        )
    }

    func testMap_whenSettingsContainsCUnsafeFlags_mapsToOtherCFlags() throws {
        let project = try subject.map(
            packageInfo: .init(
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
                platforms: []
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test("Target1", customSettings: ["OTHER_CFLAGS": ["key1", "key2", "key3"]]),
                ]
            )
        )
    }

    func testMap_whenSettingsContainsCXXUnsafeFlags_mapsToOtherCPlusPlusFlags() throws {
        let project = try subject.map(
            packageInfo: .init(
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
                platforms: []
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test("Target1", customSettings: ["OTHER_CPLUSPLUSFLAGS": ["key1", "key2", "key3"]]),
                ]
            )
        )
    }

    func testMap_whenSettingsContainsSwiftUnsafeFlags_mapsToOtherSwiftFlags() throws {
        let project = try subject.map(
            packageInfo: .init(
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
                platforms: []
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test("Target1", customSettings: ["OTHER_SWIFT_FLAGS": ["key1", "key2", "key3"]]),
                ]
            )
        )
    }

    func testMap_whenConditionalSetting_ignoresByPlatform() throws {
        let project = try subject.map(
            packageInfo: .init(
                products: [
                    .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                ],
                targets: [
                    .test(
                        name: "Target1",
                        settings: [
                            .init(tool: .c, name: .headerSearchPath, condition: .init(platformNames: ["tvos"], config: nil), value: ["value"]),
                            .init(tool: .c, name: .headerSearchPath, condition: .init(platformNames: ["ios"], config: nil), value: ["otherValue"]),
                        ]
                    ),
                ],
                platforms: []
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test("Target1", customSettings: ["HEADER_SEARCH_PATHS": ["/Package/Path/Sources/Target1/otherValue"]]),
                ]
            )
        )
    }

    func testMap_whenSettingsContainsLinkedFramework_mapsToSDKDependency() throws {
        let project = try subject.map(
            packageInfo: .init(
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
                platforms: []
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test("Target1", dependencies: [.sdk(name: "Framework.framework", status: .required)]),
                ]
            )
        )
    }

    func testMap_whenSettingsContainsLinkedLibrary_mapsToSDKDependency() throws {
        let project = try subject.map(
            packageInfo: .init(
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
                platforms: []
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test("Target1", dependencies: [.sdk(name: "Library.tbd", status: .required)]),
                ]
            )
        )
    }

    func testMap_whenTargetDependency_mapsToTargetDependency() throws {
        let project = try subject.map(
            packageInfo: .init(
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
                platforms: []
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test("Target1", dependencies: [.target(name: "Dependency1")]),
                    .test("Dependency1"),
                ]
            )
        )
    }

    func testMap_whenBinaryTargetDependency_mapsToXcFramework() throws {
        let project = try subject.map(
            packageInfo: .init(
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
                platforms: []
            ),
            targetDependencyToFramework: [
                "Dependency1": "/Path/To/Dependency1.framework",
            ]
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test("Target1", dependencies: [.xcframework(path: "/Path/To/Dependency1.framework")]),
                ]
            )
        )
    }

    func testMap_whenTargetByNameDependency_mapsToTargetDependency() throws {
        let project = try subject.map(
            packageInfo: .init(
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
                platforms: []
            )
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test("Target1", dependencies: [.target(name: "Dependency1")]),
                    .test("Dependency1"),
                ]
            )
        )
    }

    func testMap_whenBinaryTargetByNameDependency_mapsToXcFramework() throws {
        let project = try subject.map(
            packageInfo: .init(
                products: [
                    .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                ],
                targets: [
                    .test(
                        name: "Target1",
                        dependencies: [.byName(name: "Dependency1", condition: nil)]
                    ),
                    .test(name: "Dependency1", type: .binary),
                ],
                platforms: []
            ),
            targetDependencyToFramework: [
                "Dependency1": "/Path/To/Dependency1.framework",
            ]
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test("Target1", dependencies: [.xcframework(path: "/Path/To/Dependency1.framework")]),
                ]
            )
        )
    }

    func testMap_whenExternalProductDependency_mapsToProjectDependencies() throws {
        let package1 = PackageInfo(
            products: [
                .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
            ],
            targets: [
                .test(
                    name: "Target1",
                    dependencies: [.product(name: "Product2", package: "Package2", condition: nil)]
                ),
                .test(name: "Dependency1"),
            ],
            platforms: []
        )
        let package2 = PackageInfo(
            products: [
                .init(name: "Product2", type: .library(.automatic), targets: ["Target2", "Target3"]),
                .init(name: "Product3", type: .library(.automatic), targets: ["Target4"]),
            ],
            targets: [
                .test(name: "Target1"),
                .test(name: "Target2"),
                .test(name: "Target3"),
                .test(name: "Target4"),
            ],
            platforms: []
        )
        let project = try subject.map(
            packageInfo: package1,
            packageInfos: ["Package1": package1, "Package2": package2]
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test(
                        "Target1",
                        dependencies: [
                            .project(target: "Target2", path: "/Package2/Path"),
                            .project(target: "Target3", path: "/Package2/Path"),
                        ]
                    ),
                ]
            )
        )
    }

    func testMap_whenExternalByNameProductDependency_mapsToProjectDependencies() throws {
        let package1 = PackageInfo(
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
            platforms: []
        )
        let package2 = PackageInfo(
            products: [
                .init(name: "Product2", type: .library(.automatic), targets: ["Target2", "Target3"]),
                .init(name: "Product3", type: .library(.automatic), targets: ["Target4"]),
            ],
            targets: [
                .test(name: "Target1"),
                .test(name: "Target2"),
                .test(name: "Target3"),
                .test(name: "Target4"),
            ],
            platforms: []
        )
        let project = try subject.map(
            packageInfo: package1,
            packageInfos: ["Package1": package1, "Product2": package2]
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test(
                        "Target1",
                        dependencies: [
                            .project(target: "Target2", path: "/Product2/Path"),
                            .project(target: "Target3", path: "/Product2/Path"),
                        ]
                    ),
                ]
            )
        )
    }
}

extension PackageInfoMapping {
    fileprivate func map(
        packageInfo: PackageInfo,
        name: String = "Package",
        packageInfos: [String: PackageInfo] = [:],
        platforms: Set<TuistGraph.Platform> = [.iOS],
        targetDependencyToFramework: [String: Path] = [:]
    ) throws -> ProjectDescription.Project {
        return try map(
            packageInfo: packageInfo,
            packageInfos: packageInfos,
            name: name,
            path: .init("/\(name)/Path"),
            productTypes: [:],
            platforms: platforms,
            deploymentTargets: [],
            packageToProject: Dictionary(uniqueKeysWithValues: packageInfos.keys.map { ($0, "/\($0)/Path") }),
            productToPackage: packageInfos.reduce(into: [:]) { result, packageInfo in
                for product in packageInfo.value.products {
                    result[product.name] = packageInfo.key
                }
            },
            targetDependencyToFramework: targetDependencyToFramework
        )
    }
}

extension PackageInfo.Target {
    fileprivate static func test(
        name: String,
        type: PackageInfo.Target.TargetType = .regular,
        path: String? = nil,
        sources: [String]? = nil,
        resources: [PackageInfo.Target.Resource] = [],
        dependencies: [PackageInfo.Target.Dependency] = [],
        publicHeadersPath: String? = nil,
        settings: [TargetBuildSettingDescription.Setting] = []
    ) -> Self {
        return .init(
            name: name,
            path: path,
            url: nil,
            sources: sources,
            resources: resources,
            exclude: [],
            dependencies: dependencies,
            publicHeadersPath: publicHeadersPath,
            type: type,
            settings: settings,
            checksum: nil
        )
    }
}

extension ProjectDescription.Project {
    fileprivate static func test(name _: String, targets: [ProjectDescription.Target]) -> Self {
        return .init(
            name: "Package",
            targets: targets,
            resourceSynthesizers: []
        )
    }
}

extension ProjectDescription.Target {
    fileprivate static func test(
        _ name: String,
        platform: ProjectDescription.Platform = .iOS,
        customBundleID: String? = nil,
        deploymentTarget: ProjectDescription.DeploymentTarget? = nil,
        customSources: SourceFilesList? = nil,
        resources: ResourceFileElements? = nil,
        headers: ProjectDescription.Headers? = nil,
        dependencies: [ProjectDescription.TargetDependency] = [],
        customSettings: ProjectDescription.SettingsDictionary = [:]
    ) -> Self {
        return .init(
            name: name,
            platform: platform,
            product: .staticFramework,
            bundleId: customBundleID ?? name,
            deploymentTarget: deploymentTarget,
            infoPlist: .default,
            sources: customSources ?? "/Package/Path/Sources/\(name)/**",
            resources: resources,
            headers: headers,
            dependencies: dependencies,
            settings: DependenciesGraph.spmSettings(with: customSettings)
        )
    }
}
