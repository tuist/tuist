import ProjectDescription

let project = Project(
    name: "App with XPC",
    targets: [
        .target(
            name: "MainApp",
            destinations: [.mac],
            product: .app,
            bundleId: "io.tuist.MainApp",
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
            bundleId: "io.tuist.XPCApp",
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
            bundleId: "io.tuist.DynamicFramework",
            sources: ["DynamicFramework/Sources/**"]
        ),
        .target(
            name: "StaticFramework",
            destinations: [.mac],
            product: .staticFramework,
            bundleId: "io.tuist.StaticFramework",
            sources: ["StaticFramework/Sources/**"]
        ),
    ]
)
