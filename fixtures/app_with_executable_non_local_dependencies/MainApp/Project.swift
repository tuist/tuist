import ProjectDescription

let project = Project(
    name: "MainApp",
    organizationName: "tuist.io",
    targets: [
        .target(
            name: "MainApp",
            destinations: [.iPhone],
            product: .app,
            bundleId: "io.tuist.app",
            deploymentTargets: .iOS("13.0"),
            infoPlist: .default,
            sources: ["Targets/App/Sources/**"],
            dependencies: [
                .project(target: "AppExtension", path: "../HelperAppTargets"),
                .project(target: "WatchApp", path: "../HelperAppTargets"),
            ]
        ),
        .target(
            name: "MainAppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.AppTests",
            infoPlist: .default,
            sources: ["Targets/App/Tests/**"],
            dependencies: [
                .target(name: "MainApp"),
                .project(target: "TestHost", path: "../HelperAppTargets"),
            ]
        ),
    ]
)
