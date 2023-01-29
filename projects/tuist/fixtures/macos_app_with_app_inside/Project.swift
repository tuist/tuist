import ProjectDescription

let project = Project(
    name: "Embedded App",
    targets: [
        Target(
            name: "MainApp",
            platform: .macOS,
            product: .app,
            bundleId: "io.tuist.MainApp",
            infoPlist: "MainApp/Info.plist",
            sources: ["MainApp/Sources/**"],
            dependencies: [
                .target(name: "InnerApp"),
            ]
        ),
        Target(
            name: "InnerApp",
            platform: .macOS,
            product: .app,
            bundleId: "io.tuist.InnerApp",
            infoPlist: "InnerApp/Info.plist",
            sources: ["InnerApp/Sources/**"]
        ),
    ]
)
