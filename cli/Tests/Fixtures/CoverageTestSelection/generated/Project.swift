import ProjectDescription

let testSettings: Settings = .settings(base: [
    // TestCoverageAttribution is linked statically; without -ObjC an XCTest-only target drops its observer.
    "OTHER_LDFLAGS": ["$(inherited)", "-ObjC"],
])

let project = Project(
    name: "Shop",
    options: .options(
        automaticSchemesOptions: .disabled,
        disableBundleAccessors: true,
        disableSynthesizedResourceAccessors: true
    ),
    settings: .settings(configurations: [
        .debug(name: "Debug", xcconfig: "Configs/Base.xcconfig"),
        .release(name: "Release", xcconfig: "Configs/Base.xcconfig"),
    ]),
    targets: [
        .target(
            name: "Core",
            destinations: .iOS,
            product: .staticLibrary,
            bundleId: "dev.tuist.testbed.Core",
            deploymentTargets: .iOS("17.0"),
            sources: ["Core/Sources/**"]
        ),
        .target(
            name: "Catalog",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.testbed.Catalog",
            deploymentTargets: .iOS("17.0"),
            sources: ["Catalog/Sources/**"],
            resources: ["Catalog/Resources/**"]
        ),
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.testbed.App",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .extendingDefault(with: ["UILaunchScreen": ["UIColorName": ""]]),
            sources: ["App/Sources/**"],
            resources: ["App/Resources/**"],
            dependencies: [
                .target(name: "Catalog"),
                .target(name: "Core"),
            ]
        ),
        .target(
            name: "CoreTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.testbed.CoreTests",
            deploymentTargets: .iOS("17.0"),
            sources: ["CoreTests/**/*.swift"],
            dependencies: [
                .target(name: "Core"),
                .external(name: "TestCoverageAttribution"),
            ],
            settings: testSettings
        ),
        .target(
            name: "CatalogTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.testbed.CatalogTests",
            deploymentTargets: .iOS("17.0"),
            sources: ["CatalogTests/**/*.swift"],
            dependencies: [
                .target(name: "Catalog"),
                .external(name: "TestCoverageAttribution"),
            ],
            settings: testSettings
        ),
        .target(
            name: "AppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.testbed.AppTests",
            deploymentTargets: .iOS("17.0"),
            sources: ["AppTests/**/*.swift"],
            dependencies: [
                .target(name: "App"),
                .external(name: "TestCoverageAttribution"),
            ],
            settings: testSettings
        ),
        .target(
            name: "AppUITests",
            destinations: .iOS,
            product: .uiTests,
            bundleId: "dev.tuist.testbed.AppUITests",
            deploymentTargets: .iOS("17.0"),
            sources: ["AppUITests/**/*.swift"],
            dependencies: [
                .target(name: "App"),
                .external(name: "TestCoverageAttribution"),
            ],
            settings: testSettings
        ),
    ],
    schemes: [
        .scheme(
            name: "Shop",
            buildAction: .buildAction(targets: ["App"]),
            testAction: .targets(
                [
                    .testableTarget(target: "CoreTests", parallelization: .disabled),
                    .testableTarget(target: "CatalogTests", parallelization: .disabled),
                    .testableTarget(target: "AppTests", parallelization: .disabled),
                    .testableTarget(target: "AppUITests", parallelization: .disabled),
                ],
                options: .options(coverage: true)
            ),
            runAction: .runAction(executable: "App")
        ),
    ]
)
