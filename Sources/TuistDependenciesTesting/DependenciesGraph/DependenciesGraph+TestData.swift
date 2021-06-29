import Foundation
import ProjectDescription
import TSCBasic

public extension DependenciesGraph {
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
    ) -> DependenciesGraph {
        return .init(
            externalDependencies: [
                name: [.xcframework(path: path)],
            ],
            externalProjects: [:]
        )
    }

    static func test(spmFolder: Path) -> Self {
        let packageFolder = Self.packageFolder(spmFolder: spmFolder, packageName: "test")
        return .init(
            externalDependencies: [
                "Tuist": [.project(target: "Tuist", path: packageFolder)],
            ],
            externalProjects: [
                packageFolder: .init(
                    name: "test",
                    targets: [
                        .init(
                            name: "Tuist",
                            platform: .iOS,
                            product: .staticFramework,
                            bundleId: "Tuist",
                            deploymentTarget: .iOS(targetVersion: "13.0", devices: [.iphone, .ipad, .mac]),
                            infoPlist: .default,
                            sources: [
                                "\(packageFolder.pathString)/customPath/customSources/**",
                            ],
                            resources: [
                                "\(packageFolder.pathString)/customPath/resources/**",
                            ],
                            dependencies: [
                                .target(name: "TuistKit"),
                                .project(target: "ALibrary", path: "../a-dependency"),
                            ],
                            settings: Settings(
                                base: [
                                    "HEADER_SEARCH_PATHS": .array(["cSearchPath", "cxxSearchPath"]),
                                    "OTHER_CFLAGS": .array(["CUSTOM_C_FLAG"]),
                                    "OTHER_CPLUSPLUSFLAGS": .array(["CUSTOM_CXX_FLAG"]),
                                    "OTHER_SWIFT_FLAGS": .array(["CUSTOM_SWIFT_FLAG1", "CUSTOM_SWIFT_FLAG2"]),
                                    "GCC_PREPROCESSOR_DEFINITIONS": .array(["CXX_DEFINE=CXX_VALUE", "C_DEFINE=C_VALUE"]),
                                    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": .array(["SWIFT_DEFINE"]),
                                ]
                            )
                        ),
                    ],
                    resourceSynthesizers: []
                ),
            ]
        )
    }

    static func aDependency(spmFolder: Path) -> Self {
        let packageFolder = Self.packageFolder(spmFolder: spmFolder, packageName: "a-dependency")
        return .init(
            externalDependencies: [
                "ALibrary": [
                    .project(target: "ALibrary", path: packageFolder),
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
                            deploymentTarget: .iOS(targetVersion: "13.0", devices: [.iphone, .ipad, .mac]),
                            infoPlist: .default,
                            sources: [
                                "\(packageFolder.pathString)/Sources/ALibrary/**",
                            ],
                            settings: Settings()
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
                            deploymentTarget: .iOS(targetVersion: "13.0", devices: [.iphone, .ipad, .mac]),
                            infoPlist: .default,
                            sources: [
                                "\(packageFolder.pathString)/Sources/AnotherLibrary/**",
                            ],
                            settings: Settings()
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
                    targets: [
                        .init(
                            name: "Alamofire",
                            platform: .iOS,
                            product: .staticFramework,
                            bundleId: "Alamofire",
                            deploymentTarget: .iOS(targetVersion: "10.0", devices: [.iphone, .ipad, .mac]),
                            infoPlist: .default,
                            sources: [
                                "\(packageFolder.pathString)/Source/**",
                            ],
                            dependencies: [
                                .sdk(name: "CFNetwork.framework", status: .required),
                            ],
                            settings: Settings()
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
                    targets: [
                        .init(
                            name: "GoogleAppMeasurementTarget",
                            platform: .iOS,
                            product: .staticFramework,
                            bundleId: "GoogleAppMeasurementTarget",
                            deploymentTarget: .iOS(targetVersion: "10.0", devices: [.iphone, .ipad, .mac]),
                            infoPlist: .default,
                            sources: [
                                "\(packageFolder.pathString)/GoogleAppMeasurementWrapper/**",
                            ],
                            dependencies: [
                                .xcframework(path: "\(artifactsFolder.pathString)/GoogleAppMeasurement.xcframework"),
                                .project(target: "GULAppDelegateSwizzler", path: "../GoogleUtilities"),
                                .project(target: "GULMethodSwizzler", path: "../GoogleUtilities"),
                                .project(target: "GULNSData", path: "../GoogleUtilities"),
                                .project(target: "GULNetwork", path: "../GoogleUtilities"),
                                .project(target: "nanopb", path: "../nanopb"),
                                .sdk(name: "sqlite3.tbd", status: .required),
                                .sdk(name: "c++.tbd", status: .required),
                                .sdk(name: "z.tbd", status: .required),
                                .sdk(name: "StoreKit.framework", status: .required),
                            ],
                            settings: Settings()
                        ),
                        .init(
                            name: "GoogleAppMeasurementWithoutAdIdSupportTarget",
                            platform: .iOS,
                            product: .staticFramework,
                            bundleId: "GoogleAppMeasurementWithoutAdIdSupportTarget",
                            deploymentTarget: .iOS(targetVersion: "10.0", devices: [.iphone, .ipad, .mac]),
                            infoPlist: .default,
                            sources: [
                                "\(packageFolder.pathString)/GoogleAppMeasurementWithoutAdIdSupportWrapper/**",
                            ],
                            dependencies: [
                                .xcframework(path: "\(artifactsFolder.pathString)/GoogleAppMeasurementWithoutAdIdSupport.xcframework"),
                                .project(target: "GULAppDelegateSwizzler", path: "../GoogleUtilities"),
                                .project(target: "GULMethodSwizzler", path: "../GoogleUtilities"),
                                .project(target: "GULNSData", path: "../GoogleUtilities"),
                                .project(target: "GULNetwork", path: "../GoogleUtilities"),
                                .project(target: "nanopb", path: "../nanopb"),
                                .sdk(name: "sqlite3.tbd", status: .required),
                                .sdk(name: "c++.tbd", status: .required),
                                .sdk(name: "z.tbd", status: .required),
                                .sdk(name: "StoreKit.framework", status: .required),
                            ],
                            settings: Settings()
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
                            deploymentTarget: .iOS(targetVersion: "10.0", devices: [.iphone, .ipad, .mac]),
                            infoPlist: .default,
                            sources: [
                                "\(packageFolder.pathString)/Sources/GULAppDelegateSwizzler/**",
                            ],
                            settings: Settings()
                        ),
                        .init(
                            name: "GULMethodSwizzler",
                            platform: .iOS,
                            product: customProductTypes["GULMethodSwizzler"] ?? .staticFramework,
                            bundleId: "GULMethodSwizzler",
                            deploymentTarget: .iOS(targetVersion: "10.0", devices: [.iphone, .ipad, .mac]),
                            infoPlist: .default,
                            sources: [
                                "\(packageFolder.pathString)/Sources/GULMethodSwizzler/**",
                            ],
                            settings: Settings()
                        ),
                        .init(
                            name: "GULNSData",
                            platform: .iOS,
                            product: customProductTypes["GULNSData"] ?? .staticFramework,
                            bundleId: "GULNSData",
                            deploymentTarget: .iOS(targetVersion: "10.0", devices: [.iphone, .ipad, .mac]),
                            infoPlist: .default,
                            sources: [
                                "\(packageFolder.pathString)/Sources/GULNSData/**",
                            ],
                            settings: Settings()
                        ),
                        .init(
                            name: "GULNetwork",
                            platform: .iOS,
                            product: customProductTypes["GULNetwork"] ?? .staticFramework,
                            bundleId: "GULNetwork",
                            deploymentTarget: .iOS(targetVersion: "10.0", devices: [.iphone, .ipad, .mac]),
                            infoPlist: .default,
                            sources: [
                                "\(packageFolder.pathString)/Sources/GULNetwork/**",
                            ],
                            settings: Settings()
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
                            deploymentTarget: .iOS(targetVersion: "10.0", devices: [.iphone, .ipad, .mac]),
                            infoPlist: .default,
                            sources: [
                                "\(packageFolder.pathString)/Sources/nanopb/**",
                            ],
                            settings: Settings()
                        ),
                    ],
                    resourceSynthesizers: []
                ),
            ]
        )
    }
}

public extension DependenciesGraph {
    fileprivate static func artifactsFolder(spmFolder: Path, packageName: String) -> Path {
        return Path("\(spmFolder.pathString)/artifacts/\(packageName)")
    }

    fileprivate static func packageFolder(spmFolder: Path, packageName: String) -> Path {
        return Path("\(spmFolder.pathString)/checkouts/\(packageName)")
    }
}
