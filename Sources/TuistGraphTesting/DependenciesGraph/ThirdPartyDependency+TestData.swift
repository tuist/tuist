import Foundation
import TSCBasic
import TuistGraph

public extension ThirdPartyDependency {
    static func testXCFramework(
        name: String = "Test",
        path: AbsolutePath = AbsolutePath.root.appending(RelativePath("Test.xcframework")),
        architectures: Set<BinaryArchitecture> = []
    ) -> Self {
        return .xcframework(name: name, path: path, architectures: architectures)
    }

    static func test(packageFolder: AbsolutePath) -> Self {
        return .sources(
            name: "test",
            products: [
                .init(
                    name: "Tuist",
                    targets: ["Tuist"],
                    libraryType: .static
                ),
            ],
            targets: [
                .init(
                    name: "Tuist",
                    sources: [packageFolder.appending(RelativePath("customPath/customSources"))],
                    resources: [packageFolder.appending(RelativePath("customPath/resources"))],
                    dependencies: [
                        .target(name: "TuistKit"),
                        .thirdPartyTarget(dependency: "a-dependency", product: "ALibrary"),
                    ]
                ),
                .init(
                    name: "TuistKit",
                    sources: [packageFolder.appending(RelativePath("Sources/TuistKit"))],
                    resources: [],
                    dependencies: [
                        .thirdPartyTarget(dependency: "another-dependency", product: "AnotherLibrary"),
                    ]
                ),
            ],
            minDeploymentTargets: [
                .iOS("13.0", .all),
                .macOS("10.15"),
                .watchOS("6.0"),
            ]
        )
    }

    static func aDependency(packageFolder: AbsolutePath) -> Self {
        return .sources(
            name: "a-dependency",
            products: [
                .init(
                    name: "ALibrary",
                    targets: ["ALibrary"],
                    libraryType: .automatic
                ),
            ],
            targets: [
                .init(
                    name: "ALibrary",
                    sources: [packageFolder.appending(RelativePath("Sources/ALibrary"))],
                    resources: [],
                    dependencies: []
                ),
            ],
            minDeploymentTargets: [
                .iOS("13.0", .all),
                .macOS("10.15"),
                .watchOS("6.0"),
            ]
        )
    }

    static func anotherDependency(packageFolder: AbsolutePath) -> Self {
        return .sources(
            name: "another-dependency",
            products: [
                .init(
                    name: "AnotherLibrary",
                    targets: ["AnotherLibrary"],
                    libraryType: .automatic
                ),
            ],
            targets: [
                .init(
                    name: "AnotherLibrary",
                    sources: [packageFolder.appending(RelativePath("Sources/AnotherLibrary"))],
                    resources: [],
                    dependencies: []
                ),
            ],
            minDeploymentTargets: [
                .iOS("13.0", .all),
                .macOS("10.15"),
                .watchOS("6.0"),
            ]
        )
    }

    static func alamofire(packageFolder: AbsolutePath) -> Self {
        return .sources(
            name: "Alamofire",
            products: [
                .init(
                    name: "Alamofire",
                    targets: ["Alamofire"],
                    libraryType: .automatic
                ),
            ],
            targets: [
                .init(
                    name: "Alamofire",
                    sources: [packageFolder.appending(RelativePath("Source"))],
                    resources: [],
                    dependencies: []
                ),
            ],
            minDeploymentTargets: [
                .iOS("10.0", .all),
                .macOS("10.12"),
                .tvOS("10.0"),
                .watchOS("3.0"),
            ]
        )
    }
    static func googleAppMeasurement(artifactsFolder: AbsolutePath, packageFolder: AbsolutePath) -> Self {
        return .sources(
            name: "GoogleAppMeasurement",
            products: [
                .init(
                    name: "GoogleAppMeasurement",
                    targets: ["GoogleAppMeasurementTarget"],
                    libraryType: .automatic
                ),
                .init(
                    name: "GoogleAppMeasurementWithoutAdIdSupport",
                    targets: ["GoogleAppMeasurementWithoutAdIdSupportTarget"],
                    libraryType: .automatic
                ),
            ],
            targets: [
                .init(
                    name: "GoogleAppMeasurementTarget",
                    sources: [packageFolder.appending(RelativePath("GoogleAppMeasurementWrapper"))],
                    resources: [],
                    dependencies: [
                        .xcframework(path: artifactsFolder.appending(component: "GoogleAppMeasurement.xcframework")),
                        .thirdPartyTarget(dependency: "GoogleUtilities", product: "GULAppDelegateSwizzler"),
                        .thirdPartyTarget(dependency: "GoogleUtilities", product: "GULMethodSwizzler"),
                        .thirdPartyTarget(dependency: "GoogleUtilities", product: "GULNSData"),
                        .thirdPartyTarget(dependency: "GoogleUtilities", product: "GULNetwork"),
                        .thirdPartyTarget(dependency: "nanopb", product: "nanopb"),
                    ]
                ),
                .init(
                    name: "GoogleAppMeasurementWithoutAdIdSupportTarget",
                    sources: [packageFolder.appending(RelativePath("GoogleAppMeasurementWithoutAdIdSupportWrapper"))],
                    resources: [],
                    dependencies: [
                        .xcframework(path: artifactsFolder.appending(component: "GoogleAppMeasurementWithoutAdIdSupport.xcframework")),
                        .thirdPartyTarget(dependency: "GoogleUtilities", product: "GULAppDelegateSwizzler"),
                        .thirdPartyTarget(dependency: "GoogleUtilities", product: "GULMethodSwizzler"),
                        .thirdPartyTarget(dependency: "GoogleUtilities", product: "GULNSData"),
                        .thirdPartyTarget(dependency: "GoogleUtilities", product: "GULNetwork"),
                        .thirdPartyTarget(dependency: "nanopb", product: "nanopb"),
                    ]
                ),
            ],
            minDeploymentTargets: [
                .iOS("10.0", .all),
            ]
        )
    }

    // swiftlint:disable:next function_body_length
    static func googleUtilities(packageFolder: AbsolutePath) -> Self {
        return .sources(
            name: "GoogleUtilities",
            products: [
                .init(
                    name: "GULAppDelegateSwizzler",
                    targets: ["GULAppDelegateSwizzler"],
                    libraryType: .automatic
                ),
                .init(
                    name: "GULMethodSwizzler",
                    targets: ["GULMethodSwizzler"],
                    libraryType: .automatic
                ),
                .init(
                    name: "GULNSData",
                    targets: ["GULNSData"],
                    libraryType: .automatic
                ),
                .init(
                    name: "GULNetwork",
                    targets: ["GULNetwork"],
                    libraryType: .automatic
                ),
            ],
            targets: [
                .init(
                    name: "GULAppDelegateSwizzler",
                    sources: [packageFolder.appending(RelativePath("Sources/GULAppDelegateSwizzler"))],
                    resources: [],
                    dependencies: []
                ),
                .init(
                    name: "GULMethodSwizzler",
                    sources: [packageFolder.appending(RelativePath("Sources/GULMethodSwizzler"))],
                    resources: [],
                    dependencies: []
                ),
                .init(
                    name: "GULNSData",
                    sources: [packageFolder.appending(RelativePath("Sources/GULNSData"))],
                    resources: [],
                    dependencies: []
                ),
                .init(
                    name: "GULNetwork",
                    sources: [packageFolder.appending(RelativePath("Sources/GULNetwork"))],
                    resources: [],
                    dependencies: []
                ),
            ],
            minDeploymentTargets: [
                .iOS("10.0", .all),
            ]
        )
    }

    static func nanopb(packageFolder: AbsolutePath) -> Self {
        return .sources(
            name: "nanopb",
            products: [
                .init(
                    name: "nanopb",
                    targets: ["nanopb"],
                    libraryType: .automatic
                ),
            ],
            targets: [
                .init(
                    name: "nanopb",
                    sources: [packageFolder.appending(RelativePath("Sources/nanopb"))],
                    resources: [],
                    dependencies: []
                ),
            ],
            minDeploymentTargets: [
                .iOS("10.0", .all),
            ]
        )
    }
}
