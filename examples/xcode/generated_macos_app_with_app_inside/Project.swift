import ProjectDescription

let project = Project(
    name: "Embedded App",
    targets: [
        .target(
            name: "MainApp",
            destinations: [.mac],
            product: .app,
            bundleId: "dev.tuist.MainApp",
            infoPlist: "MainApp/Info.plist",
            sources: ["MainApp/Sources/**"],
            scripts: [
                .post(path: "Scripts/install_cli.sh", arguments: [], name: "Install CLI"),
            ],
            dependencies: [
                .target(name: "InnerApp"),
                .target(name: "InnerCLI"),
            ]
        ),
        .target(
            name: "InnerApp",
            destinations: [.mac],
            product: .app,
            bundleId: "dev.tuist.InnerApp",
            infoPlist: "InnerApp/Info.plist",
            sources: ["InnerApp/Sources/**"]
        ),
        .target(
            name: "InnerCLI",
            destinations: [.mac],
            product: .commandLineTool,
            bundleId: "dev.tuist.InnerCLI",
            sources: ["InnerCLI/**"]
        ),
    ]
)
