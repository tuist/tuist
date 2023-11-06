import ProjectDescription

let project = Project(
    name: "A",
    targets: [
        Target(
            name: "A",
            platform: .iOS,
            product: .staticFramework,
            bundleId: "io.tuist.A",
            infoPlist: "Info.plist",
            sources: "Sources/**",
            dependencies: [
                .project(target: "B", path: "../B"),
                .project(target: "C", path: "../C"),
                .framework(path: "../../Prebuilt/prebuilt/PrebuiltStaticFramework.framework"),
            ]
        ),
        Target(
            name: "ATests",
            platform: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.ATests",
            infoPlist: "Tests.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "A"),
            ]
        ),
    ]
)
