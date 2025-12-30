import ProjectDescription

let project = Project(
    name: "App with SystemExtension",
    targets: [
        .target(
            name: "MainApp",
            destinations: [.mac],
            product: .app,
            bundleId: "dev.tuist.MainApp",
            infoPlist: "MainApp/Info.plist",
            sources: ["MainApp/Sources/**"],
            dependencies: [
                .target(name: "SystemExtension"),
            ]
        ),
        .target(
            name: "SystemExtension",
            destinations: [.mac],
            product: .systemExtension,
            bundleId: "dev.tuist.SystemExtension",
            sources: ["SystemExtension/Sources/**"]
        ),
    ]
)
