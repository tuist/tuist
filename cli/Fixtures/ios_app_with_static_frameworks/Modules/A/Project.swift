import ProjectDescription

let project = Project(
    name: "A",
    targets: [
        .target(
            name: "A",
            destinations: .iOS,
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
        .target(
            name: "ATests",
            destinations: .iOS,
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
