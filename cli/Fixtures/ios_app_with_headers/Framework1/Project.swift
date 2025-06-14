import ProjectDescription

let project = Project(
    name: "Framework1",
    targets: [
        .target(
            name: "Framework1-iOS",
            destinations: .iOS,
            product: .framework,
            productName: "Framework1",
            bundleId: "io.tuist.Framework1",
            infoPlist: "Config/Framework1-Info.plist",
            sources: "Sources/**",
            headers: .headers(
                public: ["Sources/Public/A/**", "Sources/Public/B/**"],
                private: ["Sources/Private/**"],
                project: ["Sources/Project/**"]
            ),
            dependencies: []
        ),
        .target(
            name: "Framework1-macOS",
            destinations: [.mac],
            product: .framework,
            productName: "Framework1",
            bundleId: "io.tuist.Framework1",
            infoPlist: "Config/Framework1-Info.plist",
            sources: "Sources/**",
            headers: .headers(
                public: "Sources/Public/**",
                private: "Sources/Private/**",
                project: "Sources/Project/**"
            ),
            dependencies: []
        ),
        .target(
            name: "Framework1Tests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.Framework1Tests",
            infoPlist: "Config/Framework1Tests-Info.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "Framework1-iOS"),
            ]
        ),
    ]
)
