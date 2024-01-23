import ProjectDescription

let project = Project(
    name: "StaticFramework",
    targets: [
        Target(
            name: "StaticFramework",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "io.tuist.StaticFramework",
            infoPlist: "Support/Info.plist",
            sources: ["Sources/**"],
            headers: .headers(public: "Sources/**/*.h"),
            dependencies: [
                .sdk(name: "c++", type: .library),
            ]
        ),
        Target(
            name: "StaticFrameworkTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.StaticFrameworkTests",
            infoPlist: "Support/Tests.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "StaticFramework"),
            ]
        ),
    ]
)
