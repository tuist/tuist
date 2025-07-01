import ProjectDescription

let project = Project(
    name: "MainApp",
    organizationName: "tuist.io",
    targets: [
        .target(
            name: "MainApp",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.app",
            deploymentTargets: .iOS("13.0"),
            infoPlist: .default,
            sources: ["Targets/App/Sources/**"],
            dependencies: [
                .project(target: "AppExtension", path: "../HelperAppTargets"),
            ]
        ),
        .target(
            name: "MainAppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.AppTests",
            infoPlist: .default,
            sources: ["Targets/App/Tests/**"],
            dependencies: [
                .target(name: "MainApp"),
                .project(target: "TestHost", path: "../HelperAppTargets"),
            ],
            settings: .settings(
                base: SettingsDictionary().merging(["TEST_HOST": "$(BUILT_PRODUCTS_DIR)/TestHost.app/TestHost"])
            )
        ),
    ]
)
