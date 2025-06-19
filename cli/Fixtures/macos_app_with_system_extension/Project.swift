import ProjectDescription

let project = Project(
    name: "App with SystemExtension",
    targets: [
        .target(
            name: "MainApp",
            destinations: [.mac],
            product: .app,
            bundleId: "io.tuist.MainApp",
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
            bundleId: "io.tuist.SystemExtension",
            sources: ["SystemExtension/Sources/**"]
        ),
    ]
)
