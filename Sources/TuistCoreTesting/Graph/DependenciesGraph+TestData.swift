import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistSupport
import TuistSupportTesting

extension TuistCore.DependenciesGraph {
    /// A snapshot of `graph.json` file.
    public static var testJson: String {
        """
        {
          "externalDependencies" : {
            "RxSwift" : [
              {
                "kind" : "xcframework",
                "path" : "/Tuist/Dependencies/SwiftPackageManager/RxSwift.xcframework"
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
        // swiftlint:disable:next force_try
        path: Path = .path(AbsolutePath.root.appending(try! RelativePath(validating: "Test.xcframework")).pathString)
    ) -> Self {
        let externalDependencies = [name: [TargetDependency.xcframework(path: path)]]

        return .init(
            externalDependencies: externalDependencies,
            externalProjects: [:]
        )
    }

    // swiftlint:disable:next function_body_length
    public static func test(
        spmFolder: Path,
        packageFolder: Path,
        destinations: Destinations = [.iPhone, .iPad, .macWithiPadDesign, .appleVisionWithiPadDesign],
        fileHandler: FileHandler
    ) throws -> Self {
        try fileHandler.createFolder(try AbsolutePath(validating: "\(packageFolder.pathString)/customPath/resources"))

        let externalDependencies: [String: [TargetDependency]] = [
            "Tuist": [
                .project(
                    target: "Tuist",
                    path: packageFolder
                ),
            ],
        ]

        let targets: [Target] = [
            .target(
                name: "Tuist",
                destinations: destinations,
                product: .staticFramework,
                productName: "Tuist",
                bundleId: "Tuist",
                deploymentTargets: resolveDeploymentTargets(for: destinations),
                infoPlist: .default,
                sources: [
                    .glob(
                        "\(packageFolder.pathString)/customPath/customSources/**",
                        excluding: "\(packageFolder.pathString)/customPath/excluded/sources/**"
                    ),
                ],
                resources: [
                    .folderReference(path: "\(packageFolder.pathString)/customPath/resources", tags: []),
                ],
                dependencies: [
                    .target(name: "TuistKit"),
                    .project(
                        target: "ALibrary",
                        path: Self.packageFolder(spmFolder: spmFolder, packageName: "ADependency"),
                        condition: .when([.ios])
                    ),
                    .project(
                        target: "ALibraryUtils",
                        path: Self.packageFolder(spmFolder: spmFolder, packageName: "ADependency"),
                        condition: .when([.ios])
                    ),
                    .sdk(name: "WatchKit", type: .framework, status: .required, condition: .when([.watchos])),
                ],
                settings: Self.spmSettings(packageName: "Tuist", with: [
                    "HEADER_SEARCH_PATHS": [
                        "$(SRCROOT)/customPath/cSearchPath",
                        "$(SRCROOT)/customPath/cxxSearchPath",
                    ],
                    "OTHER_CFLAGS": ["CUSTOM_C_FLAG"],
                    "OTHER_CPLUSPLUSFLAGS": ["CUSTOM_CXX_FLAG"],
                    "OTHER_SWIFT_FLAGS": ["CUSTOM_SWIFT_FLAG1", "CUSTOM_SWIFT_FLAG2"],
                    "GCC_PREPROCESSOR_DEFINITIONS": ["CXX_DEFINE=CXX_VALUE", "C_DEFINE=C_VALUE"],
                    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "SWIFT_DEFINE",
                ])
            ),
            .target(
                name: "TuistKit",
                destinations: destinations,
                product: .staticFramework,
                productName: "TuistKit",
                bundleId: "TuistKit",
                deploymentTargets: resolveDeploymentTargets(for: destinations),
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
                settings: Self.spmSettings(packageName: "TuistKit")
            ),
        ]

        return .init(
            externalDependencies: externalDependencies,
            externalProjects: [
                packageFolder: .init(
                    name: "test",
                    options: .options(
                        automaticSchemesOptions: .disabled,
                        disableBundleAccessors: false,
                        disableSynthesizedResourceAccessors: true,
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
                    targets: targets,
                    resourceSynthesizers: .default
                ),
            ]
        )
    }

    // swiftlint:disable:next function_body_length
    public static func aDependency(
        spmFolder: Path,
        destinations: Destinations = [.iPhone, .iPad, .macWithiPadDesign, .appleVisionWithiPadDesign]
    ) -> Self {
        let packageFolder = Self.packageFolder(spmFolder: spmFolder, packageName: "ADependency")

        let externalDependencies: [String: [TargetDependency]] = [
            "ALibrary": [
                .project(
                    target: "ALibrary",
                    path: packageFolder
                ),
                .project(
                    target: "ALibraryUtils",
                    path: packageFolder
                ),
            ],
        ]

        let targets: [Target] = [
            .target(
                name: "ALibrary",
                destinations: destinations,
                product: .staticFramework,
                productName: "ALibrary",
                bundleId: "ALibrary",
                deploymentTargets: resolveDeploymentTargets(for: destinations),
                infoPlist: .default,
                sources: [
                    "\(packageFolder.pathString)/Sources/ALibrary/**",
                ],
                dependencies: [
                    .target(
                        name: "ALibraryUtils"
                    ),
                ],
                settings: Self.spmSettings(packageName: "ALibrary")
            ),
            .target(
                name: "ALibraryUtils",
                destinations: destinations,
                product: .staticFramework,
                productName: "ALibraryUtils",
                bundleId: "ALibraryUtils",
                deploymentTargets: resolveDeploymentTargets(for: destinations),
                infoPlist: .default,
                sources: [
                    "\(packageFolder.pathString)/Sources/ALibraryUtils/**",
                ],
                settings: Self.spmSettings(packageName: "ALibraryUtils")
            ),
        ]

        return .init(
            externalDependencies: externalDependencies,
            externalProjects: [
                packageFolder: .init(
                    name: "a-dependency",
                    options: .options(
                        automaticSchemesOptions: .disabled,
                        disableBundleAccessors: false,
                        disableSynthesizedResourceAccessors: true,
                        textSettings: .textSettings(usesTabs: nil, indentWidth: nil, tabWidth: nil, wrapsLines: nil)
                    ),
                    settings: .settings(
                        configurations: [
                            .debug(name: .debug),
                            .release(name: .release),
                        ]
                    ),
                    targets: targets,
                    resourceSynthesizers: .default
                ),
            ]
        )
    }

    public static func anotherDependency(
        spmFolder: Path,
        destinations: Destinations = [.iPhone, .iPad, .macWithiPadDesign, .appleVisionWithiPadDesign]
    ) -> Self {
        let packageFolder = Self.packageFolder(spmFolder: spmFolder, packageName: "another-dependency")

        let externalDependencies: [String: [TargetDependency]] = [
            "AnotherLibrary": [
                .project(
                    target: "AnotherLibrary",
                    path: packageFolder
                ),
            ],
        ]

        let targets: [Target] = [
            .target(
                name: "AnotherLibrary",
                destinations: destinations,
                product: .staticFramework,
                productName: "AnotherLibrary",
                bundleId: "AnotherLibrary",
                deploymentTargets: resolveDeploymentTargets(for: destinations),
                infoPlist: .default,
                sources: [
                    "\(packageFolder.pathString)/Sources/AnotherLibrary/**",
                ],
                settings: Self.spmSettings(packageName: "AnotherLibrary")
            ),
        ]

        return .init(
            externalDependencies: externalDependencies,
            externalProjects: [
                packageFolder: .init(
                    name: "another-dependency",
                    options: .options(
                        automaticSchemesOptions: .disabled,
                        disableBundleAccessors: false,
                        disableSynthesizedResourceAccessors: true,
                        textSettings: .textSettings(usesTabs: nil, indentWidth: nil, tabWidth: nil, wrapsLines: nil)
                    ),
                    settings: .settings(
                        configurations: [
                            .debug(name: .debug),
                            .release(name: .release),
                        ]
                    ),
                    targets: targets,
                    resourceSynthesizers: .default
                ),
            ]
        )
    }

    public static func alamofire(
        spmFolder: Path,
        destinations: Destinations = [.iPhone, .iPad, .macWithiPadDesign, .appleVisionWithiPadDesign]
    ) -> Self {
        let packageFolder = Self.packageFolder(spmFolder: spmFolder, packageName: "Alamofire")

        let externalDependencies: [String: [TargetDependency]] = [
            "Alamofire": [
                .project(
                    target: "Alamofire",
                    path: packageFolder
                ),
            ],
        ]

        let targets: [Target] = [
            .target(
                name: "Alamofire",
                destinations: destinations,
                product: .staticFramework,
                productName: "Alamofire",
                bundleId: "Alamofire",
                deploymentTargets: resolveDeploymentTargets(for: destinations),
                infoPlist: .default,
                sources: [
                    "\(packageFolder.pathString)/Source/**",
                ],
                dependencies: [
                    .sdk(
                        name: "CFNetwork",
                        type: .framework,
                        status: .required,
                        condition: .when([.ios, .macos, .tvos, .watchos])
                    ),
                ],
                settings: Self.spmSettings(packageName: "Alamofire")
            ),
        ]

        return .init(
            externalDependencies: externalDependencies,
            externalProjects: [
                packageFolder: .init(
                    name: "Alamofire",
                    options: .options(
                        automaticSchemesOptions: .disabled,
                        disableBundleAccessors: false,
                        disableSynthesizedResourceAccessors: true,
                        textSettings: .textSettings(usesTabs: nil, indentWidth: nil, tabWidth: nil, wrapsLines: nil)
                    ),
                    settings: .settings(base: ["SWIFT_VERSION": "5.0.0"]),
                    targets: targets,
                    resourceSynthesizers: .default
                ),
            ]
        )
    }

    // swiftlint:disable:next function_body_length
    public static func googleAppMeasurement(
        spmFolder: Path,
        destinations: Destinations = [.iPhone, .iPad, .macWithiPadDesign, .appleVisionWithiPadDesign]
    ) -> Self {
        let packageFolder = Self.packageFolder(spmFolder: spmFolder, packageName: "GoogleAppMeasurement")
        let artifactsFolder = Self.artifactsFolder(spmFolder: spmFolder, packageName: "GoogleAppMeasurement")

        let externalDependencies = [
            "GoogleAppMeasurement": [
                TargetDependency.project(
                    target: "GoogleAppMeasurementTarget",
                    path: packageFolder
                ),
            ],
            "GoogleAppMeasurementWithoutAdIdSupport": [
                TargetDependency.project(
                    target: "GoogleAppMeasurementWithoutAdIdSupportTarget",
                    path: packageFolder
                ),
            ],
        ]

        let targets: [Target] = [
            .target(
                name: "GoogleAppMeasurementTarget",
                destinations: destinations,
                product: .staticFramework,
                productName: "GoogleAppMeasurementTarget",
                bundleId: "GoogleAppMeasurementTarget",
                deploymentTargets: resolveDeploymentTargets(for: destinations),
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
                    .project(
                        target: "nanopb",
                        path: Self.packageFolder(spmFolder: spmFolder, packageName: "nanopb")
                    ),
                    .sdk(name: "sqlite3", type: .library, status: .required),
                    .sdk(name: "c++", type: .library, status: .required),
                    .sdk(name: "z", type: .library, status: .required),
                    .sdk(name: "StoreKit", type: .framework, status: .required),
                ],
                settings: Self.spmSettings(packageName: "GoogleAppMeasurementTarget")
            ),
            .target(
                name: "GoogleAppMeasurementWithoutAdIdSupportTarget",
                destinations: destinations,
                product: .staticFramework,
                productName: "GoogleAppMeasurementWithoutAdIdSupportTarget",
                bundleId: "GoogleAppMeasurementWithoutAdIdSupportTarget",
                deploymentTargets: resolveDeploymentTargets(for: destinations),
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
                    .project(
                        target: "nanopb",
                        path: Self.packageFolder(spmFolder: spmFolder, packageName: "nanopb")
                    ),
                    .sdk(name: "sqlite3", type: .library, status: .required),
                    .sdk(name: "c++", type: .library, status: .required),
                    .sdk(name: "z", type: .library, status: .required),
                    .sdk(name: "StoreKit", type: .framework, status: .required),
                ],
                settings: Self.spmSettings(packageName: "GoogleAppMeasurementWithoutAdIdSupportTarget")
            ),
        ]

        return .init(
            externalDependencies: externalDependencies,
            externalProjects: [
                packageFolder: .init(
                    name: "GoogleAppMeasurement",
                    options: .options(
                        automaticSchemesOptions: .disabled,
                        disableBundleAccessors: false,
                        disableSynthesizedResourceAccessors: true,
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
                    targets: targets,
                    resourceSynthesizers: .default
                ),
            ]
        )
    }

    // swiftlint:disable:next function_body_length
    public static func googleUtilities(
        spmFolder: Path,
        customProductTypes: [String: Product] = [:],
        destinations: Destinations = [.iPhone, .iPad, .macWithiPadDesign, .appleVisionWithiPadDesign]
    ) -> Self {
        let packageFolder = Self.packageFolder(spmFolder: spmFolder, packageName: "GoogleUtilities")

        let externalDependencies: [String: [TargetDependency]] = [
            "GULAppDelegateSwizzler": [
                .project(
                    target: "GULAppDelegateSwizzler",
                    path: packageFolder
                ),
            ],
            "GULMethodSwizzler": [
                .project(
                    target: "GULMethodSwizzler",
                    path: packageFolder
                ),
            ],
            "GULNSData": [
                .project(
                    target: "GULNSData",
                    path: packageFolder
                ),
            ],
            "GULNetwork": [
                .project(
                    target: "GULNetwork",
                    path: packageFolder
                ),
            ],
        ]

        let targets: [Target] = [
            .target(
                name: "GULAppDelegateSwizzler",
                destinations: destinations,
                product: customProductTypes["GULAppDelegateSwizzler"] ?? .staticFramework,
                productName: "GULAppDelegateSwizzler",
                bundleId: "GULAppDelegateSwizzler",
                deploymentTargets: resolveDeploymentTargets(for: destinations),
                infoPlist: .default,
                sources: [
                    "\(packageFolder.pathString)/Sources/GULAppDelegateSwizzler/**",
                ],
                settings: Self.spmSettings(packageName: "GULAppDelegateSwizzler")
            ),
            .target(
                name: "GULMethodSwizzler",
                destinations: destinations,
                product: customProductTypes["GULMethodSwizzler"] ?? .staticFramework,
                productName: "GULMethodSwizzler",
                bundleId: "GULMethodSwizzler",
                deploymentTargets: resolveDeploymentTargets(for: destinations),
                infoPlist: .default,
                sources: [
                    "\(packageFolder.pathString)/Sources/GULMethodSwizzler/**",
                ],
                settings: Self.spmSettings(packageName: "GULMethodSwizzler")
            ),

            .target(
                name: "GULNSData",
                destinations: destinations,
                product: customProductTypes["GULNSData"] ?? .staticFramework,
                productName: "GULNSData",
                bundleId: "GULNSData",
                deploymentTargets: resolveDeploymentTargets(for: destinations),
                infoPlist: .default,
                sources: [
                    "\(packageFolder.pathString)/Sources/GULNSData/**",
                ],
                settings: Self.spmSettings(packageName: "GULNSData")
            ),
            .target(
                name: "GULNetwork",
                destinations: destinations,
                product: customProductTypes["GULNetwork"] ?? .staticFramework,
                productName: "GULNetwork",
                bundleId: "GULNetwork",
                deploymentTargets: resolveDeploymentTargets(for: destinations),
                infoPlist: .default,
                sources: [
                    "\(packageFolder.pathString)/Sources/GULNetwork/**",
                ],
                settings: Self.spmSettings(packageName: "GULNetwork")
            ),
        ]

        return .init(
            externalDependencies: externalDependencies,
            externalProjects: [
                packageFolder: .init(
                    name: "GoogleUtilities",
                    options: .options(
                        automaticSchemesOptions: .disabled,
                        disableBundleAccessors: false,
                        disableSynthesizedResourceAccessors: true,
                        textSettings: .textSettings(usesTabs: nil, indentWidth: nil, tabWidth: nil, wrapsLines: nil)
                    ),
                    settings: .settings(
                        configurations: [
                            .debug(name: .debug),
                            .release(name: .release),
                        ]
                    ),
                    targets: targets,
                    resourceSynthesizers: .default
                ),
            ]
        )
    }

    public static func nanopb(
        spmFolder: Path,
        destinations: Destinations = [.iPhone, .iPad, .macWithiPadDesign, .appleVisionWithiPadDesign]
    ) -> Self {
        let packageFolder = Self.packageFolder(spmFolder: spmFolder, packageName: "nanopb")

        let externalDependencies = [
            "nanopb": [
                TargetDependency.project(
                    target: "nanopb",
                    path: packageFolder
                ),
            ],
        ]

        let targets: [Target] = [
            .target(
                name: "nanopb",
                destinations: destinations,
                product: .staticFramework,
                productName: "nanopb",
                bundleId: "nanopb",
                deploymentTargets: resolveDeploymentTargets(for: destinations),
                infoPlist: .default,
                sources: [
                    "\(packageFolder.pathString)/Sources/nanopb/**",
                ],
                settings: Self.spmSettings(packageName: "nanopb")
            ),
        ]

        return .init(
            externalDependencies: externalDependencies,
            externalProjects: [
                packageFolder: .init(
                    name: "nanopb",
                    options: .options(
                        automaticSchemesOptions: .disabled,
                        disableBundleAccessors: false,
                        disableSynthesizedResourceAccessors: true,
                        textSettings: .textSettings(usesTabs: nil, indentWidth: nil, tabWidth: nil, wrapsLines: nil)
                    ),
                    settings: .settings(
                        configurations: [
                            .debug(name: .debug),
                            .release(name: .release),
                        ]
                    ),
                    targets: targets,
                    resourceSynthesizers: .default
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
        packageName: String,
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
            "OTHER_SWIFT_FLAGS": ["-package-name", packageName],
        ]
        var settingsDictionary = customSettings.merging(defaultSpmSettings, uniquingKeysWith: { custom, _ in custom })

        if let moduleMap {
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

        if case let .string(swiftDefinitions) = settingsDictionary["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] {
            settingsDictionary["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] =
                .string("$(inherited) SWIFT_PACKAGE \(swiftDefinitions)")
        } else {
            settingsDictionary["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = .string("$(inherited) SWIFT_PACKAGE")
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
            base: baseSettings.base.combine(with: settingsDictionary),
            configurations: baseSettings.configurations,
            defaultSettings: baseSettings.defaultSettings
        )
    }
}

extension SettingsDictionary {
    /// Combines two `SettingsDictionary`. Instead of overriding values for a duplicate key, it combines them.
    func combine(with settings: SettingsDictionary) -> SettingsDictionary {
        merging(settings, uniquingKeysWith: { oldValue, newValue in
            let newValues: [String]
            switch newValue {
            case let .string(value):
                newValues = [value]
            case let .array(values):
                newValues = values
            }
            switch oldValue {
            case let .array(values):
                return .array(values + newValues)
            case let .string(value):
                return .array(value.split(separator: " ").map(String.init) + newValues)
            }
        })
    }
}

// MARK: - Helpers

extension DependenciesGraph {
    fileprivate static func resolveDeploymentTargets(for destinations: Destinations) -> DeploymentTargets {
        let platforms = destinations.platforms
        let applicableVersions = PLATFORM_TEST_VERSION.filter { platforms.contains($0.key) }

        return .multiplatform(
            iOS: applicableVersions[Platform.iOS],
            macOS: applicableVersions[Platform.macOS],
            watchOS: applicableVersions[Platform.watchOS],
            tvOS: applicableVersions[Platform.tvOS],
            visionOS: applicableVersions[Platform.visionOS]
        )
    }
}
