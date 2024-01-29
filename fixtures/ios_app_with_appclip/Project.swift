import ProjectDescription

let project = Project(
    name: "App",
    organizationName: "Tuist",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.App",
            infoPlist: .default,
            sources: ["App/Sources/**"],
            dependencies: [
                .target(name: "AppClip1"),
            ]
        ),
        .target(
            name: "Framework",
            destinations: .iOS,
            product: .framework,
            bundleId: "io.tuist.Framework",
            infoPlist: .default,
            sources: ["Framework/Sources/**"],
            dependencies: []
        ),
        .target(
            name: "StaticFramework",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "io.tuist.StaticFramework",
            infoPlist: .default,
            sources: ["StaticFramework/Sources/**"],
            dependencies: []
        ),
        .target(
            name: "AppClip1",
            destinations: .iOS,
            product: .appClip,
            bundleId: "io.tuist.App.Clip",
            infoPlist: .default,
            sources: ["AppClip1/Sources/**"],
            entitlements: "AppClip1/Entitlements/AppClip.entitlements",
            dependencies: [
                .target(name: "Framework"),
                .target(name: "StaticFramework"),
            ]
        ),
        .target(
            name: "AppClip1Tests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.AppClip1Tests",
            infoPlist: .default,
            sources: ["AppClip1Tests/Tests/**"],
            dependencies: [
                .target(name: "AppClip1"),
                .target(name: "StaticFramework"),
            ]
        ),
        .target(
            name: "AppClip1UITests",
            destinations: .iOS,
            product: .uiTests,
            bundleId: "io.tuist.AppClip1UITests",
            infoPlist: .default,
            sources: ["AppClip1UITests/Tests/**"],
            dependencies: [
                .target(name: "AppClip1"),
            ]
        ),
    ]
)
