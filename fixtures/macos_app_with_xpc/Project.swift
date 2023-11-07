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
            sources: ["XPCApp/Sources/**"],
            dependencies: [
                .target(name: "DynamicFramework"),
                .target(name: "StaticFramework"),
            ]
        ),
        Target(
            name: "DynamicFramework",
            platform: .macOS,
            product: .framework,
            bundleId: "io.tuist.DynamicFramework",
            sources: ["DynamicFramework/Sources/**"]
        ),
        Target(
            name: "StaticFramework",
            platform: .macOS,
            product: .staticFramework,
            bundleId: "io.tuist.StaticFramework",
            sources: ["StaticFramework/Sources/**"]
        ),
    ]
)
