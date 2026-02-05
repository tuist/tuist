import ProjectDescription

let project = Project(
    name: "ModuleA",
    targets: [
        .target(
            name: "ModuleA",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "dev.tuist.ModuleA",
            infoPlist: .default,
            sources: "Sources/**",
            headers: .headers(
                public: "Sources/Public/**",
                private: "Sources/Private/**",
                project: "Sources/Internal/**"
            )
        ),
        .target(
            name: "ModuleATests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.ModuleATests",
            infoPlist: .default,
            sources: "Tests/**",
            dependencies: [
                .target(name: "ModuleA"),
            ]
        ),
    ]
)
