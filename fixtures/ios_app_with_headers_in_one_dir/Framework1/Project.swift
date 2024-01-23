import ProjectDescription

let project = Project(
    name: "Framework1",
    targets: [
        Target(
            name: "Framework1-iOS",
            destinations: .iOS,
            product: .framework,
            productName: "Framework1",
            bundleId: "io.tuist.Framework1",
            infoPlist: "Config/Framework1-Info.plist",
            sources: "Sources/**",
            headers: .allHeaders(
                from: "Sources/**",
                umbrella: "Sources/Framework1.h",
                private: "Sources/MyPrivateClass.h"
            ),
            dependencies: []
        ),
        Target(
            name: "Framework1-macOS",
            destinations: [.mac],
            product: .framework,
            productName: "Framework1",
            bundleId: "io.tuist.Framework1",
            infoPlist: "Config/Framework1-Info.plist",
            sources: "Sources/**",
            headers: .allHeaders(
                from: "Sources/**",
                umbrella: "Sources/Framework1.h",
                private: "Sources/MyPrivateClass.h"
            ),
            dependencies: []
        ),
        Target(
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
