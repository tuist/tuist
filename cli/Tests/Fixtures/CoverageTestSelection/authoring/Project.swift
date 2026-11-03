import ProjectDescription

// Authors the plain projects: `scenarios.sh project <xcodeproj|synchronized>` generates from it.
let synchronized = Environment.synchronized.getBoolean(default: false)
let plist: Settings = .settings(base: ["GENERATE_INFOPLIST_FILE": "YES"])

func target(
    _ name: String,
    product: Product,
    folders: [String],
    excluded: [String] = [],
    dependencies: [TargetDependency],
    settings: Settings? = nil
) -> Target {
    let sources: SourceFilesList?
    let resources: ResourceFileElements?
    let buildableFolders: [BuildableFolder]
    if synchronized {
        sources = nil
        resources = nil
        buildableFolders = folders.map {
            .folder(.relativeToManifest($0), exceptions: excluded.isEmpty ? [] : [.exception(excluded: excluded)])
        }
    } else {
        let isTestTarget = product == .unitTests || product == .uiTests
        sources = isTestTarget ? ["\(name)/**/*.swift"] : ["\(name)/Sources/**"]
        resources = folders.contains("\(name)/Resources") ? ["\(name)/Resources/**"] : nil
        buildableFolders = []
    }
    return .target(
        name: name,
        destinations: .iOS,
        product: product,
        bundleId: "dev.tuist.testbed.\(name)",
        deploymentTargets: .iOS("17.0"),
        infoPlist: nil,
        sources: sources,
        resources: resources,
        buildableFolders: buildableFolders,
        dependencies: dependencies,
        settings: settings
    )
}

func testTarget(_ name: String, product: Product, dependency: String, excluded: [String] = []) -> Target {
    target(
        name,
        product: product,
        folders: [name],
        excluded: excluded,
        dependencies: [.target(name: dependency), .package(product: "TestCoverageAttribution")],
        settings: plist
    )
}

func shopScheme(name: String, coverageTargets: [TargetReference]) -> Scheme {
    .scheme(
        name: name,
        buildAction: .buildAction(targets: ["App"]),
        testAction: .targets(
            ["CoreTests", "CatalogTests", "AppTests", "CheckoutTests", "AppUITests"].map {
                .testableTarget(target: .target($0), parallelization: .enabled)
            },
            options: .options(coverage: true, codeCoverageTargets: coverageTargets)
        ),
        runAction: .runAction(executable: "App")
    )
}

let project = Project(
    name: "Shop",
    options: .options(
        automaticSchemesOptions: .disabled,
        disableBundleAccessors: true,
        disableSynthesizedResourceAccessors: true
    ),
    packages: [
        .remote(url: "https://github.com/tuist/TestCoverageAttribution", requirement: .upToNextMinor(from: "0.3.0")),
    ],
    settings: .settings(configurations: [
        .debug(name: "Debug", xcconfig: "Configs/Base.xcconfig"),
        .release(name: "Release", xcconfig: "Configs/Base.xcconfig"),
    ]),
    targets: [
        target("Core", product: .staticLibrary, folders: ["Core/Sources"], dependencies: []),
        target(
            "Catalog",
            product: .framework,
            folders: ["Catalog/Sources", "Catalog/Resources"],
            dependencies: [],
            settings: plist
        ),
        target(
            "App",
            product: .app,
            folders: ["App/Sources", "App/Resources"],
            dependencies: [.target(name: "Catalog"), .target(name: "Core")],
            settings: .settings(base: ["GENERATE_INFOPLIST_FILE": "YES", "INFOPLIST_KEY_UILaunchScreen_Generation": "YES"])
        ),
        testTarget("CoreTests", product: .unitTests, dependency: "Core"),
        // The fixture stays outside every target, as in the other variants.
        testTarget("CatalogTests", product: .unitTests, dependency: "Catalog", excluded: ["Fixtures/**"]),
        testTarget("AppTests", product: .unitTests, dependency: "App"),
        testTarget("CheckoutTests", product: .unitTests, dependency: "App"),
        testTarget("AppUITests", product: .uiTests, dependency: "App"),
    ],
    schemes: [
        shopScheme(name: "Shop", coverageTargets: []),
        shopScheme(name: "ShopAppCoverage", coverageTargets: ["App", "Catalog"]),
    ]
)
