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
