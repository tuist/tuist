import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistDependencies
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
                "path" : "/Tuist/Dependencies/Carthage/RxSwift.xcframework"
              }
            ]
          },
          "externalProjects": []
        }
        """
    }

    public static func test(
        externalDependencies: [Platform: [String: [TargetDependency]]] = [:],
        externalProjects: [Path: Project] = [:]
    ) -> Self {
        .init(externalDependencies: externalDependencies, externalProjects: externalProjects)
    }

    public static func testXCFramework(
        name: String = "Test",
        path: Path = Path(AbsolutePath.root.appending(RelativePath("Test.xcframework")).pathString),
        platforms: Set<Platform>
    ) -> Self {
        let externalDependencies: [Platform: [String: [TargetDependency]]] = platforms.reduce(into: [:]) { result, platform in
            result[platform] = [name: [.xcframework(path: path)]]
        }

        return .init(
            externalDependencies: externalDependencies,
            externalProjects: [:]
        )
    }

    // swiftlint:disable:next function_body_length
    public static func test(
        spmFolder: Path,
        packageFolder: Path,
        platforms: Set<Platform>,
        fileHandler: FileHandler
    ) throws -> Self {
        try fileHandler.createFolder(try AbsolutePath(validating: "\(packageFolder.pathString)/customPath/resources"))

        let addPlatfomSuffix = platforms.count != 1
        let externalDependencies: [Platform: [String: [TargetDependency]]] = platforms.reduce(into: [:]) { result, platform in
            result[platform] = [
                "Tuist": [
                    .project(
                        target: self.resolveTargetName(targetName: "Tuist", for: platform, addSuffix: addPlatfomSuffix),
                        path: packageFolder
                    ),
                ],
            ]
        }

        let targets: [Target] = platforms.flatMap { platform in
            [
                .init(
                    name: self.resolveTargetName(targetName: "Tuist", for: platform, addSuffix: addPlatfomSuffix),
                    platform: platform,
                    product: .staticFramework,
                    productName: "Tuist",
                    bundleId: "Tuist",
                    deploymentTarget: self.resolveDeploymentTarget(for: platform),
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
                        .target(name: self.resolveTargetName(targetName: "TuistKit", for: platform, addSuffix: addPlatfomSuffix)),
                        .project(
                            target: self.resolveTargetName(targetName: "ALibrary", for: platform, addSuffix: addPlatfomSuffix),
                            path: Self.packageFolder(spmFolder: spmFolder, packageName: "ADependency")
                        ),
                        .project(
                            target: self.resolveTargetName(
                                targetName: "ALibraryUtils",
                                for: platform,
                                addSuffix: addPlatfomSuffix
                            ),
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
                        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "SWIFT_DEFINE",
                    ])
                ),
                .init(
                    name: self.resolveTargetName(targetName: "TuistKit", for: platform, addSuffix: addPlatfomSuffix),
                    platform: platform,
                    product: .staticFramework,
                    productName: "TuistKit",
                    bundleId: "TuistKit",
                    deploymentTarget: self.resolveDeploymentTarget(for: platform),
                    infoPlist: .default,
                    sources: [
                        "\(packageFolder.pathString)/Sources/TuistKit/**",
                    ],
                    dependencies: [
                        .project(
                            target: self.resolveTargetName(
                                targetName: "AnotherLibrary",
                                for: platform,
                                addSuffix: addPlatfomSuffix
                            ),
                            path: Self.packageFolder(spmFolder: spmFolder, packageName: "another-dependency")
                        ),
                    ],
                    settings: Self.spmSettings()
                ),
            ]
        }

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
        platforms: Set<Platform>
    ) -> Self {
        let packageFolder = Self.packageFolder(spmFolder: spmFolder, packageName: "ADependency")

        let addPlatfomSuffix = platforms.count != 1

        let externalDependencies: [Platform: [String: [TargetDependency]]] = platforms.reduce(into: [:]) { result, platform in
            result[platform] = [
                "ALibrary": [
                    .project(
                        target: self.resolveTargetName(targetName: "ALibrary", for: platform, addSuffix: platforms.count != 1),
                        path: packageFolder
                    ),
                    .project(
                        target: self.resolveTargetName(
                            targetName: "ALibraryUtils",
                            for: platform,
                            addSuffix: platforms.count != 1
                        ),
                        path: packageFolder
                    ),
                ],
            ]
        }

        let targets: [Target] = platforms.flatMap { platform in
            [
                .init(
                    name: resolveTargetName(targetName: "ALibrary", for: platform, addSuffix: addPlatfomSuffix),
                    platform: platform,
                    product: .staticFramework,
                    productName: "ALibrary",
                    bundleId: "ALibrary",
                    deploymentTarget: self.resolveDeploymentTarget(for: platform),
                    infoPlist: .default,
                    sources: [
                        "\(packageFolder.pathString)/Sources/ALibrary/**",
                    ],
                    dependencies: [
                        .target(
                            name: self
                                .resolveTargetName(targetName: "ALibraryUtils", for: platform, addSuffix: addPlatfomSuffix)
                        ),
                    ],
                    settings: Self.spmSettings()
                ),
                .init(
                    name: self.resolveTargetName(targetName: "ALibraryUtils", for: platform, addSuffix: addPlatfomSuffix),
                    platform: platform,
                    product: .staticFramework,
                    productName: "ALibraryUtils",
                    bundleId: "ALibraryUtils",
                    deploymentTarget: self.resolveDeploymentTarget(for: platform),
                    infoPlist: .default,
                    sources: [
                        "\(packageFolder.pathString)/Sources/ALibraryUtils/**",
                    ],
                    settings: Self.spmSettings()
                ),
            ]
        }

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
        platforms: Set<Platform>
    ) -> Self {
        let packageFolder = Self.packageFolder(spmFolder: spmFolder, packageName: "another-dependency")

        let addPlatfomSuffix = platforms.count != 1
        let externalDependencies: [Platform: [String: [TargetDependency]]] = platforms.reduce(into: [:]) { result, platform in
            result[platform] = [
                "AnotherLibrary": [
                    .project(
                        target: self.resolveTargetName(
                            targetName: "AnotherLibrary",
                            for: platform,
                            addSuffix: platforms.count != 1
                        ),
                        path: packageFolder
                    ),
                ],
            ]
        }

        let targets: [Target] = platforms.map { platform in
            .init(
                name: self.resolveTargetName(targetName: "AnotherLibrary", for: platform, addSuffix: addPlatfomSuffix),
                platform: platform,
                product: .staticFramework,
                productName: "AnotherLibrary",
                bundleId: "AnotherLibrary",
                deploymentTarget: self.resolveDeploymentTarget(for: platform),
                infoPlist: .default,
                sources: [
                    "\(packageFolder.pathString)/Sources/AnotherLibrary/**",
                ],
                settings: Self.spmSettings()
            )
        }

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
        platforms: Set<Platform>
    ) -> Self {
        let packageFolder = Self.packageFolder(spmFolder: spmFolder, packageName: "Alamofire")

        let addPlatfomSuffix = platforms.count != 1
        let externalDependencies: [Platform: [String: [TargetDependency]]] = platforms.reduce(into: [:]) { result, platform in
            result[platform] = [
                "Alamofire": [
                    .project(
                        target: self.resolveTargetName(targetName: "Alamofire", for: platform, addSuffix: addPlatfomSuffix),
                        path: packageFolder
                    ),
                ],
            ]
        }

        let targets: [Target] = platforms.map { platform in
            .init(
                name: self.resolveTargetName(targetName: "Alamofire", for: platform, addSuffix: addPlatfomSuffix),
                platform: platform,
                product: .staticFramework,
                productName: "Alamofire",
                bundleId: "Alamofire",
                deploymentTarget: resolveDeploymentTarget(for: platform),
                infoPlist: .default,
                sources: [
                    "\(packageFolder.pathString)/Source/**",
                ],
                dependencies: [
                    .sdk(name: "CFNetwork", type: .framework, status: .required),
                ],
                settings: Self.spmSettings()
            )
        }

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
        platforms: Set<Platform>
    ) -> Self {
        let packageFolder = Self.packageFolder(spmFolder: spmFolder, packageName: "GoogleAppMeasurement")
        let artifactsFolder = Self.artifactsFolder(spmFolder: spmFolder, packageName: "GoogleAppMeasurement")

        let addPlatfomSuffix = platforms.count != 1
        let externalDependencies: [Platform: [String: [TargetDependency]]] = platforms.reduce(into: [:]) { result, platform in
            result[platform] = [
                "GoogleAppMeasurement": [
                    .project(
                        target: self.resolveTargetName(
                            targetName: "GoogleAppMeasurementTarget",
                            for: platform,
                            addSuffix: addPlatfomSuffix
                        ),
                        path: packageFolder
                    ),
                ],
                "GoogleAppMeasurementWithoutAdIdSupport": [
                    .project(
                        target: self.resolveTargetName(
                            targetName: "GoogleAppMeasurementWithoutAdIdSupportTarget",
                            for: platform,
                            addSuffix: addPlatfomSuffix
                        ),
                        path: packageFolder
                    ),
                ],
            ]
        }

        let targets: [Target] = platforms.flatMap { platform in
            [
                .init(
                    name: self.resolveTargetName(
                        targetName: "GoogleAppMeasurementTarget",
                        for: platform,
                        addSuffix: addPlatfomSuffix
                    ),
                    platform: platform,
                    product: .staticFramework,
                    productName: "GoogleAppMeasurementTarget",
                    bundleId: "GoogleAppMeasurementTarget",
                    deploymentTarget: self.resolveDeploymentTarget(for: platform),
                    infoPlist: .default,
                    sources: [
                        "\(packageFolder.pathString)/GoogleAppMeasurementWrapper/**",
                    ],
                    dependencies: [
                        .xcframework(path: "\(artifactsFolder.pathString)/GoogleAppMeasurement.xcframework"),
                        .project(
                            target: self.resolveTargetName(
                                targetName: "GULAppDelegateSwizzler",
                                for: platform,
                                addSuffix: addPlatfomSuffix
                            ),
                            path: Self.packageFolder(spmFolder: spmFolder, packageName: "GoogleUtilities")
                        ),
                        .project(
                            target: self.resolveTargetName(
                                targetName: "GULMethodSwizzler",
                                for: platform,
                                addSuffix: addPlatfomSuffix
                            ),
                            path: Self.packageFolder(spmFolder: spmFolder, packageName: "GoogleUtilities")
                        ),
                        .project(
                            target: self.resolveTargetName(targetName: "GULNSData", for: platform, addSuffix: addPlatfomSuffix),
                            path: Self.packageFolder(spmFolder: spmFolder, packageName: "GoogleUtilities")
                        ),
                        .project(
                            target: self.resolveTargetName(targetName: "GULNetwork", for: platform, addSuffix: addPlatfomSuffix),
                            path: Self.packageFolder(spmFolder: spmFolder, packageName: "GoogleUtilities")
                        ),
                        .project(
                            target: self.resolveTargetName(targetName: "nanopb", for: platform, addSuffix: addPlatfomSuffix),
                            path: Self.packageFolder(spmFolder: spmFolder, packageName: "nanopb")
                        ),
                        .sdk(name: "sqlite3", type: .library, status: .required),
                        .sdk(name: "c++", type: .library, status: .required),
                        .sdk(name: "z", type: .library, status: .required),
                        .sdk(name: "StoreKit", type: .framework, status: .required),
                    ],
                    settings: Self.spmSettings()
                ),
                .init(
                    name: self.resolveTargetName(
                        targetName: "GoogleAppMeasurementWithoutAdIdSupportTarget",
                        for: platform,
                        addSuffix: addPlatfomSuffix
                    ),
                    platform: platform,
                    product: .staticFramework,
                    productName: "GoogleAppMeasurementWithoutAdIdSupportTarget",
                    bundleId: "GoogleAppMeasurementWithoutAdIdSupportTarget",
                    deploymentTarget: self.resolveDeploymentTarget(for: platform),
                    infoPlist: .default,
                    sources: [
                        "\(packageFolder.pathString)/GoogleAppMeasurementWithoutAdIdSupportWrapper/**",
                    ],
                    dependencies: [
                        .xcframework(
                            path: "\(artifactsFolder.pathString)/GoogleAppMeasurementWithoutAdIdSupport.xcframework"
                        ),
                        .project(
                            target: self.resolveTargetName(
                                targetName: "GULAppDelegateSwizzler",
                                for: platform,
                                addSuffix: addPlatfomSuffix
                            ),
                            path: Self.packageFolder(spmFolder: spmFolder, packageName: "GoogleUtilities")
                        ),
                        .project(
                            target: self.resolveTargetName(
                                targetName: "GULMethodSwizzler",
                                for: platform,
                                addSuffix: addPlatfomSuffix
                            ),
                            path: Self.packageFolder(spmFolder: spmFolder, packageName: "GoogleUtilities")
                        ),
                        .project(
                            target: self.resolveTargetName(targetName: "GULNSData", for: platform, addSuffix: addPlatfomSuffix),
                            path: Self.packageFolder(spmFolder: spmFolder, packageName: "GoogleUtilities")
                        ),
                        .project(
                            target: self.resolveTargetName(targetName: "GULNetwork", for: platform, addSuffix: addPlatfomSuffix),
                            path: Self.packageFolder(spmFolder: spmFolder, packageName: "GoogleUtilities")
                        ),
                        .project(
                            target: self.resolveTargetName(targetName: "nanopb", for: platform, addSuffix: addPlatfomSuffix),
                            path: Self.packageFolder(spmFolder: spmFolder, packageName: "nanopb")
                        ),
                        .sdk(name: "sqlite3", type: .library, status: .required),
                        .sdk(name: "c++", type: .library, status: .required),
                        .sdk(name: "z", type: .library, status: .required),
                        .sdk(name: "StoreKit", type: .framework, status: .required),
                    ],
                    settings: Self.spmSettings()
                ),
            ]
        }

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
        platforms: Set<Platform>
    ) -> Self {
        let packageFolder = Self.packageFolder(spmFolder: spmFolder, packageName: "GoogleUtilities")

        let addPlatfomSuffix = platforms.count != 1
        let externalDependencies: [Platform: [String: [TargetDependency]]] = platforms.reduce(into: [:]) { result, platform in
            result[platform] = [
                "GULAppDelegateSwizzler": [
                    .project(
                        target: self.resolveTargetName(
                            targetName: "GULAppDelegateSwizzler",
                            for: platform,
                            addSuffix: addPlatfomSuffix
                        ),
                        path: packageFolder
                    ),
                ],
                "GULMethodSwizzler": [
                    .project(
                        target: self.resolveTargetName(
                            targetName: "GULMethodSwizzler",
                            for: platform,
                            addSuffix: addPlatfomSuffix
                        ),
                        path: packageFolder
                    ),
                ],
                "GULNSData": [
                    .project(
                        target: self.resolveTargetName(targetName: "GULNSData", for: platform, addSuffix: addPlatfomSuffix),
                        path: packageFolder
                    ),
                ],
                "GULNetwork": [
                    .project(
                        target: self.resolveTargetName(targetName: "GULNetwork", for: platform, addSuffix: addPlatfomSuffix),
                        path: packageFolder
                    ),
                ],
            ]
        }

        let targets: [Target] = platforms.flatMap { platform in
            [
                .init(
                    name: self.resolveTargetName(
                        targetName: "GULAppDelegateSwizzler",
                        for: platform,
                        addSuffix: addPlatfomSuffix
                    ),
                    platform: platform,
                    product: customProductTypes["GULAppDelegateSwizzler"] ?? .staticFramework,
                    productName: "GULAppDelegateSwizzler",
                    bundleId: "GULAppDelegateSwizzler",
                    deploymentTarget: self.resolveDeploymentTarget(for: platform),
                    infoPlist: .default,
                    sources: [
                        "\(packageFolder.pathString)/Sources/GULAppDelegateSwizzler/**",
                    ],
                    settings: Self.spmSettings()
                ),
                .init(
                    name: self.resolveTargetName(targetName: "GULMethodSwizzler", for: platform, addSuffix: addPlatfomSuffix),
                    platform: platform,
                    product: customProductTypes["GULMethodSwizzler"] ?? .staticFramework,
                    productName: "GULMethodSwizzler",
                    bundleId: "GULMethodSwizzler",
                    deploymentTarget: self.resolveDeploymentTarget(for: platform),
                    infoPlist: .default,
                    sources: [
                        "\(packageFolder.pathString)/Sources/GULMethodSwizzler/**",
                    ],
                    settings: Self.spmSettings()
                ),

                .init(
                    name: self.resolveTargetName(targetName: "GULNSData", for: platform, addSuffix: addPlatfomSuffix),
                    platform: platform,
                    product: customProductTypes["GULNSData"] ?? .staticFramework,
                    productName: "GULNSData",
                    bundleId: "GULNSData",
                    deploymentTarget: self.resolveDeploymentTarget(for: platform),
                    infoPlist: .default,
                    sources: [
                        "\(packageFolder.pathString)/Sources/GULNSData/**",
                    ],
                    settings: Self.spmSettings()
                ),
                .init(
                    name: self.resolveTargetName(targetName: "GULNetwork", for: platform, addSuffix: addPlatfomSuffix),
                    platform: platform,
                    product: customProductTypes["GULNetwork"] ?? .staticFramework,
                    productName: "GULNetwork",
                    bundleId: "GULNetwork",
                    deploymentTarget: self.resolveDeploymentTarget(for: platform),
                    infoPlist: .default,
                    sources: [
                        "\(packageFolder.pathString)/Sources/GULNetwork/**",
                    ],
                    settings: Self.spmSettings()
                ),
            ]
        }

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
        platforms: Set<Platform>
    ) -> Self {
        let packageFolder = Self.packageFolder(spmFolder: spmFolder, packageName: "nanopb")

        let addPlatfomSuffix = platforms.count != 1

        let externalDependencies: [Platform: [String: [TargetDependency]]] = platforms.reduce(into: [:]) { result, platform in
            result[platform] = [
                "nanopb": [
                    .project(
                        target: self.resolveTargetName(targetName: "nanopb", for: platform, addSuffix: platforms.count != 1),
                        path: packageFolder
                    ),
                ],
            ]
        }

        let targets: [Target] = platforms.map { platform in
            .init(
                name: self.resolveTargetName(targetName: "nanopb", for: platform, addSuffix: addPlatfomSuffix),
                platform: platform,
                product: .staticFramework,
                productName: "nanopb",
                bundleId: "nanopb",
                deploymentTarget: self.resolveDeploymentTarget(for: platform),
                infoPlist: .default,
                sources: [
                    "\(packageFolder.pathString)/Sources/nanopb/**",
                ],
                settings: Self.spmSettings()
            )
        }

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
            base: baseSettings.base.merging(settingsDictionary, uniquingKeysWith: { $1 }),
            configurations: baseSettings.configurations,
            defaultSettings: baseSettings.defaultSettings
        )
    }
}

// MARK: - Helpers

extension DependenciesGraph {
    fileprivate static func resolveTargetName(targetName: String, for platform: Platform, addSuffix: Bool) -> String {
        addSuffix ? "\(targetName)_\(platform.rawValue)" : targetName
    }

    fileprivate static func resolveDeploymentTarget(for platform: Platform) -> DeploymentTarget {
        switch platform {
        case .iOS:
            return .iOS(targetVersion: PLATFORM_TEST_VERSION[.iOS]!, devices: [.iphone, .ipad])
        case .watchOS:
            return .watchOS(targetVersion: PLATFORM_TEST_VERSION[.watchOS]!)
        case .macOS:
            return .macOS(targetVersion: PLATFORM_TEST_VERSION[.macOS]!)
        case .tvOS:
            return .tvOS(targetVersion: PLATFORM_TEST_VERSION[.tvOS]!)
        case .visionOS:
            return .visionOS(targetVersion: PLATFORM_TEST_VERSION[.visionOS]!)
        }
    }
}
