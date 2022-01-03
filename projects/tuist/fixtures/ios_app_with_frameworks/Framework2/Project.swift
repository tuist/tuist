import ProjectDescription

let project = Project(
    name: "Framework2",
    targets: [
        Target(
            name: "Framework2-iOS",
            platform: .iOS,
            product: .framework,
            productName: "Framework2",
            bundleId: "io.tuist.Framework2",
            infoPlist: "Config/Framework2-Info.plist",
            sources: "Sources/**",
            headers: .headers(
                public: "Sources/Public/**",
                private: "Sources/Private/**",
                project: "Sources/Project/**"
            ),
            dependencies: [
                .project(target: "Framework3", path: "../Framework3"),
            ]
        ),
        Target(
            name: "Framework2-macOS",
            platform: .macOS,
            product: .framework,
            productName: "Framework2",
            bundleId: "io.tuist.Framework2",
            infoPlist: "Config/Framework2-Info.plist",
            sources: "Sources/**",
            headers: .headers(
                public: "Sources/Public/**",
                private: "Sources/Private/**",
                project: "Sources/Project/**"
            ),
            dependencies: []
        ),
        Target(
            name: "Framework2Tests",
            platform: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.Framework2Tests",
            infoPlist: "Config/Framework2Tests-Info.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "Framework2-iOS"),
            ]
        ),
    ]
)
