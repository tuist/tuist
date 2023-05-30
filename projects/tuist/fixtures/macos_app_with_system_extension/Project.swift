import ProjectDescription

let project = Project(
    name: "App with SystemExtension",
    targets: [
        Target(
            name: "MainApp",
            platform: .macOS,
            product: .app,
            bundleId: "io.tuist.MainApp",
            infoPlist: "MainApp/Info.plist",
            sources: ["MainApp/Sources/**"],
            dependencies: [
                .target(name: "SystemExtension"),
            ]
        ),
        Target(
            name: "SystemExtension",
            platform: .macOS,
            product: .systemExtension,
            bundleId: "io.tuist.SystemExtension",
            sources: ["SystemExtension/Sources/**"]
        ),
    ]
)
