import ProjectDescription

let project = Project(
    name: "ModuleB",
    targets: [
        .target(
            name: "ModuleB",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "dev.tuist.ModuleB",
            infoPlist: .default,
            sources: "Sources/**",
            headers: .headers(
                public: "Sources/Public/**"
            ),
            dependencies: [
                .project(target: "ModuleA", path: "../ModuleA"),
            ]
        ),
        .target(
            name: "ModuleBTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.ModuleBTests",
            infoPlist: .default,
            sources: "Tests/**",
            dependencies: [
                .target(name: "ModuleB"),
            ]
        ),
    ]
)
