import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistDependencies

public extension TuistCore.DependenciesGraph {
    /// A snapshot of `graph.json` file.
    static var testJson: String {
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

    static func test(
        externalDependencies: [String: [TargetDependency]] = [:],
        externalProjects: [Path: Project] = [:]
    ) -> Self {
        return .init(externalDependencies: externalDependencies, externalProjects: externalProjects)
    }

    static func testXCFramework(
        name: String = "Test",
        path: Path = Path(AbsolutePath.root.appending(RelativePath("Test.xcframework")).pathString)
    ) -> Self {
        return .init(
            externalDependencies: [
                name: [.xcframework(path: path)],
            ],
            externalProjects: [:]
        )
    }

    // swiftlint:disable:next function_body_length
    static func test(spmFolder: Path, packageFolder: Path) -> Self {
        return .init(
            externalDependencies: [
                "Tuist": [.project(target: "Tuist", path: packageFolder)],
            ],
            externalProjects: [
                packageFolder: .init(
                    name: "test",
                    settings: .settings(base: [
                        "GCC_C_LANGUAGE_STANDARD": "c99",
                    ]),
                    targets: [
                        .init(
                            name: "Tuist",
                            platform: .iOS,
                            product: .staticFramework,
                            bundleId: "Tuist",
                            deploymentTarget: .iOS(targetVersion: "13.0", devices: [.iphone, .ipad]),
                            infoPlist: .default,
                            sources: [
                                .init(
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
                                .glob(
                                    pattern: "\(packageFolder.pathString)/customPath/**/*.xib",
                                    excluding: [
                                        "\(packageFolder.pathString)/customPath/excluded/sources/**"
                                    ]
                                ),
                                .glob(
                                    pattern: "\(packageFolder.pathString)/customPath/**/*.storyboard",
                                    excluding: [
                                        "\(packageFolder.pathString)/customPath/excluded/sources/**"
                                    ]
                                ),
                                .glob(
                                    pattern: "\(packageFolder.pathString)/customPath/**/*.xcdatamodeld",
                                    excluding: [
                                        "\(packageFolder.pathString)/customPath/excluded/sources/**"
                                    ]
                                ),
                                .glob(
                                    pattern: "\(packageFolder.pathString)/customPath/**/*.xcmappingmodel",
                                    excluding: [
                                        "\(packageFolder.pathString)/customPath/excluded/sources/**"
                                    ]
                                ),
                                .glob(
                                    pattern: "\(packageFolder.pathString)/customPath/**/*.xcassets",
                                    excluding: [
                                        "\(packageFolder.pathString)/customPath/excluded/sources/**"
                                    ]
                                ),
                                .glob(
                                    pattern: "\(packageFolder.pathString)/customPath/**/*.lproj",
                                    excluding: [
                                        "\(packageFolder.pathString)/customPath/excluded/sources/**"
                                    ]
                                )
                            ],
                            dependencies: [
                                .target(name: "TuistKit"),
                                .project(target: "ALibrary", path: Self.packageFolder(spmFolder: spmFolder, packageName: "ADependency")),
                                .project(target: "ALibraryUtils", path: Self.packageFolder(spmFolder: spmFolder, packageName: "ADependency")),
                            ],
                            settings: Self.spmSettings(with: [
                                "HEADER_SEARCH_PATHS": ["$(SRCROOT)/customPath/cSearchPath", "$(SRCROOT)/customPath/cxxSearchPath"],
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
                            resources: [
                                "\(packageFolder.pathString)/Sources/TuistKit/**/*.xib",
                                "\(packageFolder.pathString)/Sources/TuistKit/**/*.storyboard",
                                "\(packageFolder.pathString)/Sources/TuistKit/**/*.xcdatamodeld",
                                "\(packageFolder.pathString)/Sources/TuistKit/**/*.xcmappingmodel",
                                "\(packageFolder.pathString)/Sources/TuistKit/**/*.xcassets",
                                "\(packageFolder.pathString)/Sources/TuistKit/**/*.lproj",
                            ],
                            dependencies: [
                                .project(target: "AnotherLibrary", path: Self.packageFolder(spmFolder: spmFolder, packageName: "another-dependency")),
                            ],
                            settings: Self.spmSettings()
                        ),
                    ],
                    resourceSynthesizers: []
                ),
            ]
        )
    }

    static func aDependency(spmFolder: Path) -> Self {
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
                    targets: [
                        .init(
                            name: "ALibrary",
                            platform: .iOS,
                            product: .staticFramework,
                            bundleId: "ALibrary",
                            deploymentTarget: .iOS(targetVersion: "13.0", devices: [.iphone, .ipad]),
                            infoPlist: .default,
                            sources: [
                                "\(packageFolder.pathString)/Sources/ALibrary/**",
                            ],
                            resources: [
                                "\(packageFolder.pathString)/Sources/ALibrary/**/*.xib",
                                "\(packageFolder.pathString)/Sources/ALibrary/**/*.storyboard",
                                "\(packageFolder.pathString)/Sources/ALibrary/**/*.xcdatamodeld",
                                "\(packageFolder.pathString)/Sources/ALibrary/**/*.xcmappingmodel",
                                "\(packageFolder.pathString)/Sources/ALibrary/**/*.xcassets",
                                "\(packageFolder.pathString)/Sources/ALibrary/**/*.lproj",
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
                            deploymentTarget: .iOS(targetVersion: "13.0", devices: [.iphone, .ipad]),
                            infoPlist: .default,
                            sources: [
                                "\(packageFolder.pathString)/Sources/ALibraryUtils/**",
                            ],
                            resources: [
                                "\(packageFolder.pathString)/Sources/ALibraryUtils/**/*.xib",
                                "\(packageFolder.pathString)/Sources/ALibraryUtils/**/*.storyboard",
                                "\(packageFolder.pathString)/Sources/ALibraryUtils/**/*.xcdatamodeld",
                                "\(packageFolder.pathString)/Sources/ALibraryUtils/**/*.xcmappingmodel",
                                "\(packageFolder.pathString)/Sources/ALibraryUtils/**/*.xcassets",
                                "\(packageFolder.pathString)/Sources/ALibraryUtils/**/*.lproj",
                            ],
                            settings: Self.spmSettings()
                        ),
                    ],
                    resourceSynthesizers: []
                ),
            ]
        )
    }

    static func anotherDependency(spmFolder: Path) -> Self {
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
                            resources: [
                                "\(packageFolder.pathString)/Sources/AnotherLibrary/**/*.xib",
                                "\(packageFolder.pathString)/Sources/AnotherLibrary/**/*.storyboard",
                                "\(packageFolder.pathString)/Sources/AnotherLibrary/**/*.xcdatamodeld",
                                "\(packageFolder.pathString)/Sources/AnotherLibrary/**/*.xcmappingmodel",
                                "\(packageFolder.pathString)/Sources/AnotherLibrary/**/*.xcassets",
                                "\(packageFolder.pathString)/Sources/AnotherLibrary/**/*.lproj",
                            ],
                            settings: Self.spmSettings()
                        ),
                    ],
                    resourceSynthesizers: []
                ),
            ]
        )
    }

    static func alamofire(spmFolder: Path) -> Self {
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
                            resources: [
                                "\(packageFolder.pathString)/Source/**/*.xib",
                                "\(packageFolder.pathString)/Source/**/*.storyboard",
                                "\(packageFolder.pathString)/Source/**/*.xcdatamodeld",
                                "\(packageFolder.pathString)/Source/**/*.xcmappingmodel",
                                "\(packageFolder.pathString)/Source/**/*.xcassets",
                                "\(packageFolder.pathString)/Source/**/*.lproj",
                            ],
                            dependencies: [
                                .sdk(name: "CFNetwork.framework", status: .required),
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
    static func googleAppMeasurement(spmFolder: Path) -> Self {
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
                    settings: .settings(base: [
                        "GCC_C_LANGUAGE_STANDARD": "c99",
                        "CLANG_CXX_LANGUAGE_STANDARD": "gnu++14",
                    ]),
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
                            resources: [
                                "\(packageFolder.pathString)/GoogleAppMeasurementWrapper/**/*.xib",
                                "\(packageFolder.pathString)/GoogleAppMeasurementWrapper/**/*.storyboard",
                                "\(packageFolder.pathString)/GoogleAppMeasurementWrapper/**/*.xcdatamodeld",
                                "\(packageFolder.pathString)/GoogleAppMeasurementWrapper/**/*.xcmappingmodel",
                                "\(packageFolder.pathString)/GoogleAppMeasurementWrapper/**/*.xcassets",
                                "\(packageFolder.pathString)/GoogleAppMeasurementWrapper/**/*.lproj",
                            ],              
                            dependencies: [
                                .xcframework(path: "\(artifactsFolder.pathString)/GoogleAppMeasurement.xcframework"),
                                .project(
                                    target: "GULAppDelegateSwizzler",
                                    path: Self.packageFolder(spmFolder: spmFolder, packageName: "GoogleUtilities")
                                ),
                                .project(target: "GULMethodSwizzler", path: Self.packageFolder(spmFolder: spmFolder, packageName: "GoogleUtilities")),
                                .project(target: "GULNSData", path: Self.packageFolder(spmFolder: spmFolder, packageName: "GoogleUtilities")),
                                .project(target: "GULNetwork", path: Self.packageFolder(spmFolder: spmFolder, packageName: "GoogleUtilities")),
                                .project(target: "nanopb", path: Self.packageFolder(spmFolder: spmFolder, packageName: "nanopb")),
                                .sdk(name: "libsqlite3.tbd", status: .required),
                                .sdk(name: "libc++.tbd", status: .required),
                                .sdk(name: "libz.tbd", status: .required),
                                .sdk(name: "StoreKit.framework", status: .required),
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
                            resources: [
                                "\(packageFolder.pathString)/GoogleAppMeasurementWithoutAdIdSupportWrapper/**/*.xib",
                                "\(packageFolder.pathString)/GoogleAppMeasurementWithoutAdIdSupportWrapper/**/*.storyboard",
                                "\(packageFolder.pathString)/GoogleAppMeasurementWithoutAdIdSupportWrapper/**/*.xcdatamodeld",
                                "\(packageFolder.pathString)/GoogleAppMeasurementWithoutAdIdSupportWrapper/**/*.xcmappingmodel",
                                "\(packageFolder.pathString)/GoogleAppMeasurementWithoutAdIdSupportWrapper/**/*.xcassets",
                                "\(packageFolder.pathString)/GoogleAppMeasurementWithoutAdIdSupportWrapper/**/*.lproj",
                            ],
                            dependencies: [
                                .xcframework(path: "\(artifactsFolder.pathString)/GoogleAppMeasurementWithoutAdIdSupport.xcframework"),
                                .project(
                                    target: "GULAppDelegateSwizzler",
                                    path: Self.packageFolder(spmFolder: spmFolder, packageName: "GoogleUtilities")
                                ),
                                .project(target: "GULMethodSwizzler", path: Self.packageFolder(spmFolder: spmFolder, packageName: "GoogleUtilities")),
                                .project(target: "GULNSData", path: Self.packageFolder(spmFolder: spmFolder, packageName: "GoogleUtilities")),
                                .project(target: "GULNetwork", path: Self.packageFolder(spmFolder: spmFolder, packageName: "GoogleUtilities")),
                                .project(target: "nanopb", path: Self.packageFolder(spmFolder: spmFolder, packageName: "nanopb")),
                                .sdk(name: "libsqlite3.tbd", status: .required),
                                .sdk(name: "libc++.tbd", status: .required),
                                .sdk(name: "libz.tbd", status: .required),
                                .sdk(name: "StoreKit.framework", status: .required),
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
    static func googleUtilities(spmFolder: Path, customProductTypes: [String: Product] = [:]) -> Self {
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
                            resources: [
                                "\(packageFolder.pathString)/Sources/GULAppDelegateSwizzler/**/*.xib",
                                "\(packageFolder.pathString)/Sources/GULAppDelegateSwizzler/**/*.storyboard",
                                "\(packageFolder.pathString)/Sources/GULAppDelegateSwizzler/**/*.xcdatamodeld",
                                "\(packageFolder.pathString)/Sources/GULAppDelegateSwizzler/**/*.xcmappingmodel",
                                "\(packageFolder.pathString)/Sources/GULAppDelegateSwizzler/**/*.xcassets",
                                "\(packageFolder.pathString)/Sources/GULAppDelegateSwizzler/**/*.lproj",
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
                            resources: [
                                "\(packageFolder.pathString)/Sources/GULMethodSwizzler/**/*.xib",
                                "\(packageFolder.pathString)/Sources/GULMethodSwizzler/**/*.storyboard",
                                "\(packageFolder.pathString)/Sources/GULMethodSwizzler/**/*.xcdatamodeld",
                                "\(packageFolder.pathString)/Sources/GULMethodSwizzler/**/*.xcmappingmodel",
                                "\(packageFolder.pathString)/Sources/GULMethodSwizzler/**/*.xcassets",
                                "\(packageFolder.pathString)/Sources/GULMethodSwizzler/**/*.lproj",
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
                            resources: [
                                "\(packageFolder.pathString)/Sources/GULNSData/**/*.xib",
                                "\(packageFolder.pathString)/Sources/GULNSData/**/*.storyboard",
                                "\(packageFolder.pathString)/Sources/GULNSData/**/*.xcdatamodeld",
                                "\(packageFolder.pathString)/Sources/GULNSData/**/*.xcmappingmodel",
                                "\(packageFolder.pathString)/Sources/GULNSData/**/*.xcassets",
                                "\(packageFolder.pathString)/Sources/GULNSData/**/*.lproj",
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
                            resources: [
                                "\(packageFolder.pathString)/Sources/GULNetwork/**/*.xib",
                                "\(packageFolder.pathString)/Sources/GULNetwork/**/*.storyboard",
                                "\(packageFolder.pathString)/Sources/GULNetwork/**/*.xcdatamodeld",
                                "\(packageFolder.pathString)/Sources/GULNetwork/**/*.xcmappingmodel",
                                "\(packageFolder.pathString)/Sources/GULNetwork/**/*.xcassets",
                                "\(packageFolder.pathString)/Sources/GULNetwork/**/*.lproj",
                            ],
                            settings: Self.spmSettings()
                        ),
                    ],
                    resourceSynthesizers: []
                ),
            ]
        )
    }

    static func nanopb(spmFolder: Path) -> Self {
        let packageFolder = Self.packageFolder(spmFolder: spmFolder, packageName: "nanopb")
        return .init(
            externalDependencies: [
                "nanopb": [.project(target: "nanopb", path: packageFolder)],
            ],
            externalProjects: [
                packageFolder: .init(
                    name: "nanopb",
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
                            resources: [
                                "\(packageFolder.pathString)/Sources/nanopb/**/*.xib",
                                "\(packageFolder.pathString)/Sources/nanopb/**/*.storyboard",
                                "\(packageFolder.pathString)/Sources/nanopb/**/*.xcdatamodeld",
                                "\(packageFolder.pathString)/Sources/nanopb/**/*.xcmappingmodel",
                                "\(packageFolder.pathString)/Sources/nanopb/**/*.xcassets",
                                "\(packageFolder.pathString)/Sources/nanopb/**/*.lproj",
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
        return Path("\(spmFolder.pathString)/artifacts/\(packageName)")
    }

    fileprivate static func packageFolder(spmFolder: Path, packageName: String) -> Path {
        return Path("\(spmFolder.pathString)/checkouts/\(packageName)")
    }

    static func spmSettings(
        with customSettings: SettingsDictionary = [:],
        moduleMap: String? = nil
    ) -> Settings {
        let defaultSpmSettings: SettingsDictionary = [
            "ALWAYS_SEARCH_USER_PATHS": "YES",
            "GCC_WARN_INHIBIT_ALL_WARNINGS": "YES",
            "CLANG_ENABLE_OBJC_WEAK": "NO",
            "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "NO",
            "ENABLE_STRICT_OBJC_MSGSEND": "NO",
            "ENABLE_TESTING_SEARCH_PATHS": "YES",
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
            settingsDictionary["GCC_PREPROCESSOR_DEFINITIONS"] = .array(["$(inherited)"] + (cDefinitions + ["SWIFT_PACKAGE=1"]).sorted())
        } else {
            settingsDictionary["GCC_PREPROCESSOR_DEFINITIONS"] = .array(["$(inherited)", "SWIFT_PACKAGE=1"])
        }

        if case let .array(swiftDefinitions) = settingsDictionary["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] {
            settingsDictionary["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = .array(["$(inherited)"] + ["SWIFT_PACKAGE"] + swiftDefinitions)
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

        return .settings(base: settingsDictionary)
    }
}
