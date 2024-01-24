import ProjectDescription

let project = Project(
    name: "Embedded App",
    targets: [
        Target(
            name: "MainApp",
            destinations: [.mac],
            product: .app,
            bundleId: "io.tuist.MainApp",
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
        Target(
            name: "InnerApp",
            destinations: [.mac],
            product: .app,
            bundleId: "io.tuist.InnerApp",
            infoPlist: "InnerApp/Info.plist",
            sources: ["InnerApp/Sources/**"]
        ),
        Target(
            name: "InnerCLI",
            destinations: [.mac],
            product: .commandLineTool,
            bundleId: "io.tuist.InnerCLI",
            sources: ["InnerCLI/**"]
        ),
    ]
)
