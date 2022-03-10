import ProjectDescription

let project = Project(
    name: "App",
    organizationName: "tuist.io",
    targets: [
        Target(
            name: "App",
            platform: .iOS,
            product: .app,
            bundleId: "io.tuist.app",
            deploymentTarget: .iOS(targetVersion: "13.0", devices: .iphone),
            infoPlist: .default,
            sources: ["Targets/App/Sources/**"],
            dependencies: [
                .target(name: "Dbundle"),
            ]
        ),
        Target(
            name: "Dload",
            platform: .iOS,
            product: .framework,
            bundleId: "io.tuist.Dload",
            deploymentTarget: .iOS(targetVersion: "13.0", devices: .iphone),
            infoPlist: .default,
            sources: ["Targets/Dload/Sources/**"]
        ),
        Target(
            name: "Dbundle",
            platform: .iOS,
            product: .bundle,
            bundleId: "io.tuist.Dbundle",
            deploymentTarget: .iOS(targetVersion: "13.0", devices: .iphone),
            infoPlist: .default,
            sources: ["Targets/Dbundle/Sources/**"],
            dependencies: [
                .target(name: "Dload"),
            ]
        ),
    ]
)
