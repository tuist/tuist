import ProjectDescription
import TSCBasic
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
    }

    override func tearDown() {
        subject = nil

        super.tearDown()
    }

    func testMap() throws {
        let project = try subject.map(
            package: "Package",
            packageInfos: [
                "Package": .init(
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(name: "Target1"),
                    ],
                    platforms: []
                ),
            ]
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
            package: "Package",
            packageInfos: [
                "Package": .init(
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target_1"]),
                    ],
                    targets: [
                        .test(name: "Target_1"),
                    ],
                    platforms: []
                ),
            ]
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
            package: "Package",
            packageInfos: [
                "Package": .init(
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(name: "Target1"),
                        .test(name: "Target2"),
                    ],
                    platforms: []
                ),
            ]
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
            package: "Package",
            packageInfos: [
                "Package": .init(
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1", "Target2", "Target3"]),
                    ],
                    targets: [
                        .test(name: "Target1"),
                        .test(name: "Target2", type: .test),
                        .test(name: "Target3", type: .binary),
                    ],
                    platforms: []
                ),
            ]
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
            package: "Package",
            packageInfos: [
                "Package": .init(
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
                ),
            ]
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
            package: "Package",
            packageInfos: [
                "Package": .init(
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(name: "Target1", sources: ["Subfolder", "Another/Subfolder/file.swift"]),
                    ],
                    platforms: []
                ),
            ]
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
            package: "Package",
            packageInfos: [
                "Package": .init(
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
                ),
            ]
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

    func testMap_whenHasHeadersWithCustomModuleMap() throws {
        let basePath = try temporaryPath()
        let headersPath = basePath.appending(RelativePath("Package/Path/Sources/Target1/include"))
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
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1"
                        ),
                    ],
                    platforms: []
                ),
            ]
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test(
                        "Target1",
                        basePath: basePath,
                        customSettings: [
                            "HEADER_SEARCH_PATHS": ["$(SRCROOT)/Sources/Target1/include"],
                        ],
                        moduleMap: moduleMapPath
                    ),
                ]
            )
        )
    }

    func testMap_whenHasHeadersWithUmbrellaHeader() throws {
        let basePath = try temporaryPath()
        let headersPath = basePath.appending(RelativePath("Package/Path/Sources/Target1/include"))
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
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1"
                        ),
                    ],
                    platforms: []
                ),
            ]
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test(
                        "Target1",
                        basePath: basePath,
                        headers: .init(public: [nestedHeaderPath.pathString, topHeaderPath.pathString]),
                        customSettings: [
                            "HEADER_SEARCH_PATHS": ["$(SRCROOT)/Sources/Target1/include"],
                        ]
                    ),
                ]
            )
        )
    }

    func testMap_whenDependenciesHaveHeaders() throws {
        let basePath = try temporaryPath()
        let target1HeadersPath = basePath.appending(RelativePath("Package/Path/Sources/Target1/include"))
        let target1ModuleMapPath = target1HeadersPath.appending(component: "module.modulemap")
        let dependency1HeadersPath = basePath.appending(RelativePath("Package/Path/Sources/Dependency1/include"))
        let dependency1ModuleMapPath = dependency1HeadersPath.appending(component: "module.modulemap")
        let dependency2HeadersPath = basePath.appending(RelativePath("Package/Path/Sources/Dependency2/include"))
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
                    platforms: []
                ),
            ]
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test(
                        "Target1",
                        basePath: basePath,
                        dependencies: [.target(name: "Dependency1")],
                        customSettings: [
                            "HEADER_SEARCH_PATHS": [
                                "$(SRCROOT)/Sources/Target1/include",
                                "$(SRCROOT)/Sources/Dependency1/include",
                                "$(SRCROOT)/Sources/Dependency2/include",
                            ],
                        ],
                        moduleMap: target1ModuleMapPath
                    ),
                    .test(
                        "Dependency1",
                        basePath: basePath,
                        dependencies: [.target(name: "Dependency2")],
                        customSettings: [
                            "HEADER_SEARCH_PATHS": [
                                "$(SRCROOT)/Sources/Dependency1/include",
                                "$(SRCROOT)/Sources/Dependency2/include",
                            ],
                        ],
                        moduleMap: dependency1ModuleMapPath
                    ),
                    .test(
                        "Dependency2",
                        basePath: basePath,
                        customSettings: [
                            "HEADER_SEARCH_PATHS": ["$(SRCROOT)/Sources/Dependency2/include"],
                        ],
                        moduleMap: dependency2ModuleMapPath
                    ),
                ]
            )
        )
    }

    func testMap_whenExternalDependenciesHaveHeaders() throws {
        let basePath = try temporaryPath()
        let target1HeadersPath = basePath.appending(RelativePath("Package/Path/Sources/Target1/include"))
        let target1ModuleMapPath = target1HeadersPath.appending(component: "module.modulemap")
        let dependency1HeadersPath = basePath.appending(RelativePath("Package2/Path/Sources/Dependency1/include"))
        let dependency1ModuleMapPath = dependency1HeadersPath.appending(component: "module.modulemap")
        let dependency2HeadersPath = basePath.appending(RelativePath("Package3/Path/Sources/Dependency2/include"))
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
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(
                            name: "Target1",
                            dependencies: [.product(name: "Dependency1", package: "Package2", condition: nil)]
                        ),
                    ],
                    platforms: []
                ),
                "Package2": .init(
                    products: [
                        .init(name: "Dependency1", type: .library(.automatic), targets: ["Dependency1"]),
                    ],
                    targets: [
                        .test(
                            name: "Dependency1",
                            dependencies: [.product(name: "Dependency2", package: "Package3", condition: nil)]
                        ),
                    ],
                    platforms: []
                ),
                "Package3": .init(
                    products: [
                        .init(name: "Dependency2", type: .library(.automatic), targets: ["Dependency2"]),
                    ],
                    targets: [
                        .test(
                            name: "Dependency2"
                        ),
                    ],
                    platforms: []
                ),
            ]
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test(
                        "Target1",
                        basePath: basePath,
                        dependencies: [.project(target: "Dependency1", path: Path("\(basePath.pathString)/Package2/Path"))],
                        customSettings: [
                            "HEADER_SEARCH_PATHS": [
                                "$(SRCROOT)/Sources/Target1/include",
                                "$(SRCROOT)/../../Package2/Path/Sources/Dependency1/include",
                                "$(SRCROOT)/../../Package3/Path/Sources/Dependency2/include",
                            ],
                        ],
                        moduleMap: target1ModuleMapPath
                    ),
                ]
            )
        )
    }

    func testMap_whenCustomPath() throws {
        let basePath = try temporaryPath()
        let headersPath = basePath.appending(RelativePath("Package/Path/Custom/Path/Headers"))
        let headerPath = headersPath.appending(component: "module.modulemap")
        let moduleMapPath = headersPath.appending(component: "module.modulemap")
        try fileHandler.createFolder(headersPath)
        try fileHandler.write("", path: headerPath, atomically: true)
        try fileHandler.write("", path: moduleMapPath, atomically: true)

        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
                ),
            ]
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test(
                        "Target1",
                        basePath: basePath,
                        customSources: .init(globs: [basePath.appending(RelativePath("Package/Path/Custom/Path/Sources/Folder/**")).pathString]),
                        resources: .init(resources: [
                            .init(stringLiteral: basePath.appending(RelativePath("Package/Path/Custom/Path/Resource/Folder/**")).pathString),
                        ]),
                        customSettings: [
                            "HEADER_SEARCH_PATHS": ["$(SRCROOT)/Custom/Path/Headers"],
                        ],
                        moduleMap: moduleMapPath
                    ),
                ]
            )
        )
    }

    func testMap_whenDependencyHasHeaders_addsThemToHeaderSearchPath() throws {
        let basePath = try temporaryPath()
        let dependencyHeadersPath = basePath.appending(RelativePath("Package/Path/Sources/Dependency1/include"))
        try fileHandler.createFolder(dependencyHeadersPath)
        let project = try subject.map(
            package: "Package",
            basePath: basePath,
            packageInfos: [
                "Package": .init(
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
                ),
            ]
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test(
                        "Target1",
                        basePath: basePath,
                        dependencies: [.target(name: "Dependency1")],
                        customSettings: [
                            "HEADER_SEARCH_PATHS": ["$(SRCROOT)/Sources/Dependency1/include"],
                        ]
                    ),
                    .test(
                        "Dependency1",
                        basePath: basePath,
                        customSettings: [
                            "HEADER_SEARCH_PATHS": ["$(SRCROOT)/Sources/Dependency1/include"],
                        ],
                        moduleMap: dependencyHeadersPath.appending(RelativePath("Dependency1.modulemap"))
                    ),
                ]
            )
        )
    }

    func testMap_whenIOSAvailable_takesIOS() throws {
        let project = try subject.map(
            package: "Package",
            packageInfos: [
                "Package": .init(
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(name: "Target1"),
                    ],
                    platforms: []
                ),
            ],
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
            package: "Package",
            packageInfos: [
                "Package": .init(
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(name: "Target1"),
                    ],
                    platforms: []
                ),
            ],
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
                package: "Package",
                packageInfos: [
                    "Package": .init(
                        products: [
                            .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                        ],
                        targets: [
                            .test(name: "Target1"),
                        ],
                        platforms: [.init(platformName: "tvos", version: "13.0", options: [])]
                    ),
                ],
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
            package: "Package",
            packageInfos: [
                "Package": .init(
                    products: [
                        .init(name: "Product1", type: .library(.automatic), targets: ["Target1"]),
                    ],
                    targets: [
                        .test(name: "Target1"),
                    ],
                    platforms: [.init(platformName: "ios", version: "13.0", options: [])]
                ),
            ],
            platforms: [.iOS]
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test("Target1", platform: .iOS, deploymentTarget: .iOS(targetVersion: "13.0", devices: [.iphone, .ipad])),
                ]
            )
        )
    }

    func testMap_whenSettingsContainsCHeaderSearchPath_mapsToHeaderSearchPathsSetting() throws {
        let project = try subject.map(
            package: "Package",
            packageInfos: [
                "Package": .init(
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
                ),
            ]
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test("Target1", customSettings: ["HEADER_SEARCH_PATHS": ["$(SRCROOT)/Sources/Target1/value"]]),
                ]
            )
        )
    }

    func testMap_whenSettingsContainsCXXHeaderSearchPath_mapsToHeaderSearchPathsSetting() throws {
        let project = try subject.map(
            package: "Package",
            packageInfos: [
                "Package": .init(
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
                ),
            ]
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test("Target1", customSettings: ["HEADER_SEARCH_PATHS": ["$(SRCROOT)/Sources/Target1/value"]]),
                ]
            )
        )
    }

    func testMap_whenSettingsContainsCDefine_mapsToGccPreprocessorDefinitions() throws {
        let project = try subject.map(
            package: "Package",
            packageInfos: [
                "Package": .init(
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
                ),
            ]
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
            package: "Package",
            packageInfos: [
                "Package": .init(
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
                ),
            ]
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
            package: "Package",
            packageInfos: [
                "Package": .init(
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
                ),
            ]
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
            package: "Package",
            packageInfos: [
                "Package": .init(
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
                ),
            ]
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
            package: "Package",
            packageInfos: [
                "Package": .init(
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
                ),
            ]
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
            package: "Package",
            packageInfos: [
                "Package": .init(
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
                ),
            ]
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
            package: "Package",
            packageInfos: [
                "Package": .init(
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
                ),
            ]
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test("Target1", customSettings: ["HEADER_SEARCH_PATHS": ["$(SRCROOT)/Sources/Target1/otherValue"]]),
                ]
            )
        )
    }

    func testMap_whenSettingsContainsLinkedFramework_mapsToSDKDependency() throws {
        let project = try subject.map(
            package: "Package",
            packageInfos: [
                "Package": .init(
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
                ),
            ]
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
            package: "Package",
            packageInfos: [
                "Package": .init(
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
                ),
            ]
        )
        XCTAssertEqual(
            project,
            .test(
                name: "Package",
                targets: [
                    .test("Target1", dependencies: [.sdk(name: "libLibrary.tbd", status: .required)]),
                ]
            )
        )
    }

    func testMap_whenTargetDependency_mapsToTargetDependency() throws {
        let project = try subject.map(
            package: "Package",
            packageInfos: [
                "Package": .init(
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
                ),
            ]
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
            package: "Package",
            packageInfos: [
                "Package": .init(
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
            ],
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
            package: "Package",
            packageInfos: [
                "Package": .init(
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
                ),
            ]
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
            package: "Package",
            packageInfos: [
                "Package": .init(
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
            ],
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
                .test(name: "Target2"),
                .test(name: "Target3"),
                .test(name: "Target4"),
            ],
            platforms: []
        )
        let project = try subject.map(
            package: "Package",
            packageInfos: ["Package": package1, "Package2": package2]
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
                .test(name: "Target2"),
                .test(name: "Target3"),
                .test(name: "Target4"),
            ],
            platforms: []
        )
        let project = try subject.map(
            package: "Package",
            packageInfos: ["Package": package1, "Product2": package2]
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
        package: String,
        basePath: AbsolutePath = "/",
        packageInfos: [String: PackageInfo] = [:],
        platforms: Set<TuistGraph.Platform> = [.iOS],
        targetDependencyToFramework: [String: Path] = [:]
    ) throws -> ProjectDescription.Project {
        let productToPackage: [String: String] = packageInfos.reduce(into: [:]) { result, packageInfo in
            for product in packageInfo.value.products {
                result[product.name] = packageInfo.key
            }
        }

        let (targetToProducts, targetToResolvedDependencies) = try preprocess(
            packageInfos: packageInfos, productToPackage: productToPackage, targetDependencyToFramework: targetDependencyToFramework
        )

        return try map(
            packageInfo: packageInfos[package]!,
            packageInfos: packageInfos,
            name: package,
            path: basePath.appending(component: package).appending(component: "Path"),
            productTypes: [:],
            platforms: platforms,
            deploymentTargets: [],
            targetToProducts: targetToProducts,
            targetToResolvedDependencies: targetToResolvedDependencies,
            packageToProject: Dictionary(uniqueKeysWithValues: packageInfos.keys.map {
                ($0, basePath.appending(component: $0).appending(component: "Path"))
            }
            ),
            productToPackage: productToPackage
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
    fileprivate static func test(name: String, targets: [ProjectDescription.Target]) -> Self {
        return .init(
            name: name,
            targets: targets,
            resourceSynthesizers: []
        )
    }
}

extension ProjectDescription.Target {
    fileprivate static func test(
        _ name: String,
        basePath: AbsolutePath = "/",
        platform: ProjectDescription.Platform = .iOS,
        customBundleID: String? = nil,
        deploymentTarget: ProjectDescription.DeploymentTarget? = nil,
        customSources: SourceFilesList? = nil,
        resources: ResourceFileElements? = nil,
        headers: ProjectDescription.Headers? = nil,
        dependencies: [ProjectDescription.TargetDependency] = [],
        customSettings: ProjectDescription.SettingsDictionary = [:],
        moduleMap: AbsolutePath? = nil
    ) -> Self {
        return .init(
            name: name,
            platform: platform,
            product: .staticFramework,
            bundleId: customBundleID ?? name,
            deploymentTarget: deploymentTarget,
            infoPlist: .default,
            sources: customSources ?? .init(globs: [basePath.appending(RelativePath("Package/Path/Sources/\(name)/**")).pathString]),
            resources: resources,
            headers: headers,
            dependencies: dependencies,
            settings: DependenciesGraph.spmSettings(with: customSettings, moduleMap: moduleMap)
        )
    }
}
