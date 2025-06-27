import ProjectDescription

let project = Project(
    name: "App with XPC",
    targets: [
        .target(
            name: "MainApp",
            destinations: [.mac],
            product: .app,
            bundleId: "dev.tuist.MainApp",
            infoPlist: "MainApp/Info.plist",
            sources: ["MainApp/Sources/**"],
            dependencies: [
                .target(name: "XPCApp"),
            ]
        ),
        .target(
            name: "XPCApp",
            destinations: [.mac],
            product: .xpc,
            bundleId: "dev.tuist.XPCApp",
            sources: ["XPCApp/Sources/**"],
            dependencies: [
                .target(name: "DynamicFramework"),
                .target(name: "StaticFramework"),
            ]
        ),
        .target(
            name: "DynamicFramework",
            destinations: [.mac],
            product: .framework,
            bundleId: "dev.tuist.DynamicFramework",
            sources: ["DynamicFramework/Sources/**"]
        ),
        .target(
            name: "StaticFramework",
            destinations: [.mac],
            product: .staticFramework,
            bundleId: "dev.tuist.StaticFramework",
            sources: ["StaticFramework/Sources/**"]
        ),
    ]
)
