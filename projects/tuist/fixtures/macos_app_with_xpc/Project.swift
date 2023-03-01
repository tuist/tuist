import ProjectDescription

let project = Project(
    name: "App with XPC",
    targets: [
        Target(
            name: "MainApp",
            platform: .macOS,
            product: .app,
            bundleId: "io.tuist.MainApp",
            infoPlist: "MainApp/Info.plist",
            sources: ["MainApp/Sources/**"],
            scripts: [
                .post(path: "Scripts/install_xpc.sh", arguments: [], name: "Install XPC", basedOnDependencyAnalysis: false),
            ],
            dependencies: [
                .target(name: "XPCApp"),
            ]
        ),
        Target(
            name: "XPCApp",
            platform: .macOS,
            product: .xpc,
            bundleId: "io.tuist.XPCApp",
            sources: ["XPCApp/Sources/**"]
        ),
    ]
)
