import ProjectDescription

let project = Project(
    name: "CachedXCTestSupport",
    organizationName: "tuist.dev",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.CachedXCTestSupport",
            infoPlist: .default,
            sources: ["App/Sources/**"],
            dependencies: [
                .target(name: "Feature"),
            ]
        ),
        .target(
            name: "Feature",
            destinations: .iOS,
            product: .framework,
            bundleId: "io.tuist.CachedXCTestSupport.Feature",
            infoPlist: .default,
            sources: ["Feature/Sources/**"],
            resources: ["Feature/Resources/**"]
        ),
        .target(
            name: "TestSupport",
            destinations: .iOS,
            product: .framework,
            bundleId: "io.tuist.CachedXCTestSupport.TestSupport",
            infoPlist: .default,
            sources: ["TestSupport/Sources/**"],
            resources: ["TestSupport/Resources/**"],
            dependencies: [
                .xctest,
            ],
            settings: .settings(base: [
                "ENABLE_TESTING_SEARCH_PATHS": "YES",
            ])
        ),
        .target(
            name: "SwiftTestingSupport",
            destinations: .iOS,
            product: .framework,
            bundleId: "io.tuist.CachedXCTestSupport.SwiftTestingSupport",
            infoPlist: .default,
            sources: ["SwiftTestingSupport/Sources/**"],
            resources: ["SwiftTestingSupport/Resources/**"],
            dependencies: [
                .sdk(name: "Testing", type: .framework),
            ],
            settings: .settings(base: [
                "ENABLE_TESTING_SEARCH_PATHS": "YES",
            ])
        ),
        .target(
            name: "AppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.CachedXCTestSupport.AppTests",
            infoPlist: .default,
            sources: ["App/Tests/**"],
            dependencies: [
                .target(name: "App"),
                .target(name: "Feature"),
                .target(name: "TestSupport"),
                .target(name: "SwiftTestingSupport"),
            ]
        ),
    ]
)
