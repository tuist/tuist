import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistDependencies

extension TuistCore.DependenciesGraph {
    /// A snapshot of `graph.json` file.
    public static var testJson: String {
        """
        {
          "externalDependencies" : {
            "RxSwift" : [
              {
                "kind" : "xcframework",
                "path" : "/Tuist/Dependencies/Carthage/RxSwift.xcframework"
              }
            ]
          },
          "externalProjects": []
        }
        """
    }

    public static func test(
        externalDependencies: [String: [TargetDependency]] = [:],
        externalProjects: [Path: Project] = [:]
    ) -> Self {
        .init(externalDependencies: externalDependencies, externalProjects: externalProjects)
    }

    public static func testXCFramework(
        name: String = "Test",
        path: Path = Path(AbsolutePath.root.appending(RelativePath("Test.xcframework")).pathString)
    ) -> Self {
        .init(
            externalDependencies: [
                name: [.xcframework(path: path)],
            ],
            externalProjects: [:]
        )
    }

    // swiftlint:disable:next function_body_length
    public static func test(spmFolder: Path, packageFolder: Path) -> Self {
        .init(
            externalDependencies: [
                "Tuist": [.project(target: "Tuist", path: packageFolder)],
            ],
            externalProjects: [
                packageFolder: .init(
                    name: "test",
                    options: .options(
                        automaticSchemesOptions: .disabled,
                        disableBundleAccessors: false,
                        disableSynthesizedResourceAccessors: false,
                        textSettings: .textSettings(usesTabs: nil, indentWidth: nil, tabWidth: nil, wrapsLines: nil)
                    ),
                    settings: .settings(
                        base: [
                            "GCC_C_LANGUAGE_STANDARD": "c99",
                        ],
                        configurations: [
                            .debug(name: .debug),
                            .release(name: .release),
                        ]
                    ),
                    targets: [
                        .init(
                            name: "Tuist",
                            platform: .iOS,
                            product: .staticFramework,
                            bundleId: "Tuist",
                            deploymentTarget: .iOS(targetVersion: "13.0", devices: [.iphone, .ipad]),
                            infoPlist: .default,
                            sources: [
                                .glob(
                                    "\(packageFolder.pathString)/customPath/customSources/**",
                                    excluding: "\(packageFolder.pathString)/customPath/excluded/sources/**"
                                ),
                            ],
                            resources: [
                                .glob(
                                    pattern: "\(packageFolder.pathString)/customPath/resources/**",
                                    excluding: [
                                        "\(packageFolder.pathString)/customPath/excluded/sources/**",
                                    ],
                                    tags: []
                                ),
                            ],
                            dependencies: [
                                .target(name: "TuistKit"),
                                .project(
                                    target: "ALibrary",
                                    path: Self.packageFolder(spmFolder: spmFolder, packageName: "ADependency")
                                ),
                                .project(
                                    target: "ALibraryUtils",
                                    path: Self.packageFolder(spmFolder: spmFolder, packageName: "ADependency")
                                ),
                            ],
                            settings: Self.spmSettings(with: [
                                "HEADER_SEARCH_PATHS": [
                                    "$(SRCROOT)/customPath/cSearchPath",
                                    "$(SRCROOT)/customPath/cxxSearchPath",
                                ],
                                "OTHER_CFLAGS": ["CUSTOM_C_FLAG"],
                                "OTHER_CPLUSPLUSFLAGS": ["CUSTOM_CXX_FLAG"],
                                "OTHER_SWIFT_FLAGS": ["CUSTOM_SWIFT_FLAG1", "CUSTOM_SWIFT_FLAG2"],
                                "GCC_PREPROCESSOR_DEFINITIONS": ["CXX_DEFINE=CXX_VALUE", "C_DEFINE=C_VALUE"],
                                "SWIFT_ACTIVE_COMPILATION_CONDITIONS": ["SWIFT_DEFINE"],
                            ])
                        ),
                        .init(
                            name: "TuistKit",
                            platform: .iOS,
                            product: .staticFramework,
                            bundleId: "TuistKit",
                            deploymentTarget: .iOS(targetVersion: "13.0", devices: [.iphone, .ipad]),
                            infoPlist: .default,
                            sources: [
                                "\(packageFolder.pathString)/Sources/TuistKit/**",
                            ],
                            dependencies: [
                                .project(
                                    target: "AnotherLibrary",
                                    path: Self.packageFolder(spmFolder: spmFolder, packageName: "another-dependency")
                                ),
                            ],
                            settings: Self.spmSettings()
                        ),
                    ],
                    resourceSynthesizers: []
                ),
            ]
        )
    }

    // swiftlint:disable:next function_body_length
    public static func aDependency(spmFolder: Path) -> Self {
        let packageFolder = Self.packageFolder(spmFolder: spmFolder, packageName: "ADependency")
        return .init(
            externalDependencies: [
                "ALibrary": [
                    .project(target: "ALibrary", path: packageFolder),
                    .project(target: "ALibraryUtils", path: packageFolder),
                ],
            ],
            externalProjects: [
                packageFolder: .init(
                    name: "a-dependency",
                    options: .options(
                        automaticSchemesOptions: .disabled,
                        disableBundleAccessors: false,
                        disableSynthesizedResourceAccessors: false,
                        textSettings: .textSettings(usesTabs: nil, indentWidth: nil, tabWidth: nil, wrapsLines: nil)
                    ),
                    settings: .settings(
                        configurations: [
                            .debug(name: .debug),
                            .release(name: .release),
                        ]
                    ),
                    targets: [
                        .init(
                            name: "ALibrary",
                            platform: .iOS,
                            product: .staticFramework,
                            bundleId: "ALibrary",
                            deploymentTarget: .iOS(targetVersion: "9.0", devices: [.iphone, .ipad]),
                            infoPlist: .default,
                            sources: [
                                "\(packageFolder.pathString)/Sources/ALibrary/**",
                            ],
                            dependencies: [
                                .target(name: "ALibraryUtils"),
                            ],
                            settings: Self.spmSettings()
                        ),
                        .init(
                            name: "ALibraryUtils",
                            platform: .iOS,
                            product: .staticFramework,
                            bundleId: "ALibraryUtils",
                            deploymentTarget: .iOS(targetVersion: "9.0", devices: [.iphone, .ipad]),
                            infoPlist: .default,
                            sources: [
                                "\(packageFolder.pathString)/Sources/ALibraryUtils/**",
                            ],
                            settings: Self.spmSettings()
                        ),
                    ],
                    resourceSynthesizers: []
                ),
            ]
        )
    }

    public static func anotherDependency(spmFolder: Path) -> Self {
        let packageFolder = Self.packageFolder(spmFolder: spmFolder, packageName: "another-dependency")
        return .init(
            externalDependencies: [
                "AnotherLibrary": [
                    .project(target: "AnotherLibrary", path: packageFolder),
                ],
            ],
            externalProjects: [
                packageFolder: .init(
                    name: "another-dependency",
                    options: .options(
                        automaticSchemesOptions: .disabled,
                        disableBundleAccessors: false,
                        disableSynthesizedResourceAccessors: false,
                        textSettings: .textSettings(usesTabs: nil, indentWidth: nil, tabWidth: nil, wrapsLines: nil)
                    ),
                    settings: .settings(
                        configurations: [
                            .debug(name: .debug),
                            .release(name: .release),
                        ]
                    ),
                    targets: [
                        .init(
                            name: "AnotherLibrary",
                            platform: .iOS,
                            product: .staticFramework,
                            bundleId: "AnotherLibrary",
                            deploymentTarget: .iOS(targetVersion: "13.0", devices: [.iphone, .ipad]),
                            infoPlist: .default,
                            sources: [
                                "\(packageFolder.pathString)/Sources/AnotherLibrary/**",
                            ],
                            settings: Self.spmSettings()
                        ),
                    ],
                    resourceSynthesizers: []
                ),
            ]
        )
    }

    public static func alamofire(spmFolder: Path) -> Self {
        let packageFolder = Self.packageFolder(spmFolder: spmFolder, packageName: "Alamofire")
        return .init(
            externalDependencies: [
                "Alamofire": [
                    .project(target: "Alamofire", path: packageFolder),
                ],
            ],
            externalProjects: [
                packageFolder: .init(
                    name: "Alamofire",
                    options: .options(
                        automaticSchemesOptions: .disabled,
                        disableBundleAccessors: false,
                        disableSynthesizedResourceAccessors: false,
                        textSettings: .textSettings(usesTabs: nil, indentWidth: nil, tabWidth: nil, wrapsLines: nil)
                    ),
                    settings: .settings(base: ["SWIFT_VERSION": "5.0.0"]),
                    targets: [
                        .init(
                            name: "Alamofire",
                            platform: .iOS,
                            product: .staticFramework,
                            bundleId: "Alamofire",
                            deploymentTarget: .iOS(targetVersion: "10.0", devices: [.iphone, .ipad]),
                            infoPlist: .default,
                            sources: [
                                "\(packageFolder.pathString)/Source/**",
                            ],
                            dependencies: [
                                .sdk(name: "CFNetwork", type: .framework, status: .required),
                            ],
                            settings: Self.spmSettings()
                        ),
                    ],
                    resourceSynthesizers: []
                ),
            ]
        )
    }

    // swiftlint:disable:next function_body_length
    public static func googleAppMeasurement(spmFolder: Path) -> Self {
        let packageFolder = Self.packageFolder(spmFolder: spmFolder, packageName: "GoogleAppMeasurement")
        let artifactsFolder = Self.artifactsFolder(spmFolder: spmFolder, packageName: "GoogleAppMeasurement")

        return .init(
            externalDependencies: [
                "GoogleAppMeasurement": [
                    .project(target: "GoogleAppMeasurementTarget", path: packageFolder),
                ],
                "GoogleAppMeasurementWithoutAdIdSupport": [
                    .project(target: "GoogleAppMeasurementWithoutAdIdSupportTarget", path: packageFolder),
                ],
            ],
            externalProjects: [
                packageFolder: .init(
                    name: "GoogleAppMeasurement",
                    options: .options(
                        automaticSchemesOptions: .disabled,
                        disableBundleAccessors: false,
                        disableSynthesizedResourceAccessors: false,
                        textSettings: .textSettings(usesTabs: nil, indentWidth: nil, tabWidth: nil, wrapsLines: nil)
                    ),
                    settings: .settings(
                        base: [
                            "GCC_C_LANGUAGE_STANDARD": "c99",
                            "CLANG_CXX_LANGUAGE_STANDARD": "gnu++14",
                        ],
                        configurations: [
                            .debug(name: .debug),
                            .release(name: .release),
                        ]
                    ),
                    targets: [
                        .init(
                            name: "GoogleAppMeasurementTarget",
                            platform: .iOS,
                            product: .staticFramework,
                            bundleId: "GoogleAppMeasurementTarget",
                            deploymentTarget: .iOS(targetVersion: "10.0", devices: [.iphone, .ipad]),
                            infoPlist: .default,
                            sources: [
                                "\(packageFolder.pathString)/GoogleAppMeasurementWrapper/**",
                            ],
                            dependencies: [
                                .xcframework(path: "\(artifactsFolder.pathString)/GoogleAppMeasurement.xcframework"),
                                .project(
                                    target: "GULAppDelegateSwizzler",
                                    path: Self.packageFolder(spmFolder: spmFolder, packageName: "GoogleUtilities")
                                ),
                                .project(
                                    target: "GULMethodSwizzler",
                                    path: Self.packageFolder(spmFolder: spmFolder, packageName: "GoogleUtilities")
                                ),
                                .project(
                                    target: "GULNSData",
                                    path: Self.packageFolder(spmFolder: spmFolder, packageName: "GoogleUtilities")
                                ),
                                .project(
                                    target: "GULNetwork",
                                    path: Self.packageFolder(spmFolder: spmFolder, packageName: "GoogleUtilities")
                                ),
                                .project(target: "nanopb", path: Self.packageFolder(spmFolder: spmFolder, packageName: "nanopb")),
                                .sdk(name: "sqlite3", type: .library, status: .required),
                                .sdk(name: "c++", type: .library, status: .required),
                                .sdk(name: "z", type: .library, status: .required),
                                .sdk(name: "StoreKit", type: .framework, status: .required),
                            ],
                            settings: Self.spmSettings()
                        ),
                        .init(
                            name: "GoogleAppMeasurementWithoutAdIdSupportTarget",
                            platform: .iOS,
                            product: .staticFramework,
                            bundleId: "GoogleAppMeasurementWithoutAdIdSupportTarget",
                            deploymentTarget: .iOS(targetVersion: "10.0", devices: [.iphone, .ipad]),
                            infoPlist: .default,
                            sources: [
                                "\(packageFolder.pathString)/GoogleAppMeasurementWithoutAdIdSupportWrapper/**",
                            ],
                            dependencies: [
                                .xcframework(
                                    path: "\(artifactsFolder.pathString)/GoogleAppMeasurementWithoutAdIdSupport.xcframework"
                                ),
                                .project(
                                    target: "GULAppDelegateSwizzler",
                                    path: Self.packageFolder(spmFolder: spmFolder, packageName: "GoogleUtilities")
                                ),
                                .project(
                                    target: "GULMethodSwizzler",
                                    path: Self.packageFolder(spmFolder: spmFolder, packageName: "GoogleUtilities")
                                ),
                                .project(
                                    target: "GULNSData",
                                    path: Self.packageFolder(spmFolder: spmFolder, packageName: "GoogleUtilities")
                                ),
                                .project(
                                    target: "GULNetwork",
                                    path: Self.packageFolder(spmFolder: spmFolder, packageName: "GoogleUtilities")
                                ),
                                .project(target: "nanopb", path: Self.packageFolder(spmFolder: spmFolder, packageName: "nanopb")),
                                .sdk(name: "sqlite3", type: .library, status: .required),
                                .sdk(name: "c++", type: .library, status: .required),
                                .sdk(name: "z", type: .library, status: .required),
                                .sdk(name: "StoreKit", type: .framework, status: .required),
                            ],
                            settings: Self.spmSettings()
                        ),
                    ],
                    resourceSynthesizers: []
                ),
            ]
        )
    }

    // swiftlint:disable:next function_body_length
    public static func googleUtilities(spmFolder: Path, customProductTypes: [String: Product] = [:]) -> Self {
        let packageFolder = Self.packageFolder(spmFolder: spmFolder, packageName: "GoogleUtilities")
        return .init(
            externalDependencies: [
                "GULAppDelegateSwizzler": [.project(target: "GULAppDelegateSwizzler", path: packageFolder)],
                "GULMethodSwizzler": [.project(target: "GULMethodSwizzler", path: packageFolder)],
                "GULNSData": [.project(target: "GULNSData", path: packageFolder)],
                "GULNetwork": [.project(target: "GULNetwork", path: packageFolder)],
            ],
            externalProjects: [
                packageFolder: .init(
                    name: "GoogleUtilities",
                    options: .options(
                        automaticSchemesOptions: .disabled,
                        disableBundleAccessors: false,
                        disableSynthesizedResourceAccessors: false,
                        textSettings: .textSettings(usesTabs: nil, indentWidth: nil, tabWidth: nil, wrapsLines: nil)
                    ),
                    settings: .settings(
                        configurations: [
                            .debug(name: .debug),
                            .release(name: .release),
                        ]
                    ),
                    targets: [
                        .init(
                            name: "GULAppDelegateSwizzler",
                            platform: .iOS,
                            product: customProductTypes["GULAppDelegateSwizzler"] ?? .staticFramework,
                            bundleId: "GULAppDelegateSwizzler",
                            deploymentTarget: .iOS(targetVersion: "10.0", devices: [.iphone, .ipad]),
                            infoPlist: .default,
                            sources: [
                                "\(packageFolder.pathString)/Sources/GULAppDelegateSwizzler/**",
                            ],
                            settings: Self.spmSettings()
                        ),
                        .init(
                            name: "GULMethodSwizzler",
                            platform: .iOS,
                            product: customProductTypes["GULMethodSwizzler"] ?? .staticFramework,
                            bundleId: "GULMethodSwizzler",
                            deploymentTarget: .iOS(targetVersion: "10.0", devices: [.iphone, .ipad]),
                            infoPlist: .default,
                            sources: [
                                "\(packageFolder.pathString)/Sources/GULMethodSwizzler/**",
                            ],
                            settings: Self.spmSettings()
                        ),
                        .init(
                            name: "GULNSData",
                            platform: .iOS,
                            product: customProductTypes["GULNSData"] ?? .staticFramework,
                            bundleId: "GULNSData",
                            deploymentTarget: .iOS(targetVersion: "10.0", devices: [.iphone, .ipad]),
                            infoPlist: .default,
                            sources: [
                                "\(packageFolder.pathString)/Sources/GULNSData/**",
                            ],
                            settings: Self.spmSettings()
                        ),
                        .init(
                            name: "GULNetwork",
                            platform: .iOS,
                            product: customProductTypes["GULNetwork"] ?? .staticFramework,
                            bundleId: "GULNetwork",
                            deploymentTarget: .iOS(targetVersion: "10.0", devices: [.iphone, .ipad]),
                            infoPlist: .default,
                            sources: [
                                "\(packageFolder.pathString)/Sources/GULNetwork/**",
                            ],
                            settings: Self.spmSettings()
                        ),
                    ],
                    resourceSynthesizers: []
                ),
            ]
        )
    }

    public static func nanopb(spmFolder: Path) -> Self {
        let packageFolder = Self.packageFolder(spmFolder: spmFolder, packageName: "nanopb")
        return .init(
            externalDependencies: [
                "nanopb": [.project(target: "nanopb", path: packageFolder)],
            ],
            externalProjects: [
                packageFolder: .init(
                    name: "nanopb",
                    options: .options(
                        automaticSchemesOptions: .disabled,
                        disableBundleAccessors: false,
                        disableSynthesizedResourceAccessors: false,
                        textSettings: .textSettings(usesTabs: nil, indentWidth: nil, tabWidth: nil, wrapsLines: nil)
                    ),
                    settings: .settings(
                        configurations: [
                            .debug(name: .debug),
                            .release(name: .release),
                        ]
                    ),
                    targets: [
                        .init(
                            name: "nanopb",
                            platform: .iOS,
                            product: .staticFramework,
                            bundleId: "nanopb",
                            deploymentTarget: .iOS(targetVersion: "10.0", devices: [.iphone, .ipad]),
                            infoPlist: .default,
                            sources: [
                                "\(packageFolder.pathString)/Sources/nanopb/**",
                            ],
                            settings: Self.spmSettings()
                        ),
                    ],
                    resourceSynthesizers: []
                ),
            ]
        )
    }
}

extension DependenciesGraph {
    fileprivate static func artifactsFolder(spmFolder: Path, packageName: String) -> Path {
        Path("\(spmFolder.pathString)/artifacts/\(packageName)")
    }

    fileprivate static func packageFolder(spmFolder: Path, packageName: String) -> Path {
        Path("\(spmFolder.pathString)/checkouts/\(packageName)")
    }

    static func spmSettings(
        baseSettings: Settings = .settings(),
        with customSettings: SettingsDictionary = [:],
        moduleMap: String? = nil
    ) -> Settings {
        let defaultSpmSettings: SettingsDictionary = [
            "ALWAYS_SEARCH_USER_PATHS": "YES",
            "GCC_WARN_INHIBIT_ALL_WARNINGS": "YES",
            "SWIFT_SUPPRESS_WARNINGS": "YES",
            "CLANG_ENABLE_OBJC_WEAK": "NO",
            "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "NO",
            "ENABLE_STRICT_OBJC_MSGSEND": "NO",
            "FRAMEWORK_SEARCH_PATHS": ["$(inherited)", "$(PLATFORM_DIR)/Developer/Library/Frameworks"],
            "GCC_NO_COMMON_BLOCKS": "NO",
            "USE_HEADERMAP": "NO",
        ]
        var settingsDictionary = customSettings.merging(defaultSpmSettings, uniquingKeysWith: { custom, _ in custom })

        if let moduleMap = moduleMap {
            settingsDictionary["MODULEMAP_FILE"] = .string(moduleMap)
        }

        if case let .array(headerSearchPaths) = settingsDictionary["HEADER_SEARCH_PATHS"] {
            settingsDictionary["HEADER_SEARCH_PATHS"] = .array(["$(inherited)"] + headerSearchPaths)
        }

        if case let .array(cDefinitions) = settingsDictionary["GCC_PREPROCESSOR_DEFINITIONS"] {
            settingsDictionary["GCC_PREPROCESSOR_DEFINITIONS"] = .array(
                ["$(inherited)"] + (cDefinitions + ["SWIFT_PACKAGE=1"])
                    .sorted()
            )
        } else {
            settingsDictionary["GCC_PREPROCESSOR_DEFINITIONS"] = .array(["$(inherited)", "SWIFT_PACKAGE=1"])
        }

        if case let .array(swiftDefinitions) = settingsDictionary["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] {
            settingsDictionary["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] =
                .array(["$(inherited)"] + ["SWIFT_PACKAGE"] + swiftDefinitions)
        } else {
            settingsDictionary["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = .array(["$(inherited)"] + ["SWIFT_PACKAGE"])
        }

        if case let .array(cFlags) = settingsDictionary["OTHER_CFLAGS"] {
            settingsDictionary["OTHER_CFLAGS"] = .array(["$(inherited)"] + cFlags)
        }

        if case let .array(cxxFlags) = settingsDictionary["OTHER_CPLUSPLUSFLAGS"] {
            settingsDictionary["OTHER_CPLUSPLUSFLAGS"] = .array(["$(inherited)"] + cxxFlags)
        }

        if case let .array(swiftFlags) = settingsDictionary["OTHER_SWIFT_FLAGS"] {
            settingsDictionary["OTHER_SWIFT_FLAGS"] = .array(["$(inherited)"] + swiftFlags)
        }

        if case let .array(linkerFlags) = settingsDictionary["OTHER_LDFLAGS"] {
            settingsDictionary["OTHER_LDFLAGS"] = .array(["$(inherited)"] + linkerFlags)
        }

        return .settings(
            base: baseSettings.base.merging(settingsDictionary, uniquingKeysWith: { $1 }),
            configurations: baseSettings.configurations,
            defaultSettings: baseSettings.defaultSettings
        )
    }
}
