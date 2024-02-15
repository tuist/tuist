import ProjectDescription

let project = Project(
    name: "StaticFrameworkA",
    targets: [
        .target(
            name: "StaticFrameworkA",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "io.tuist.StaticFrameworkA",
            infoPlist: .default,
            sources: ["Sources/**"],
            dependencies: [
                .project(target: "StaticFrameworkB", path: "../StaticFrameworkB"),
                .xcframework(path: "../../XCFrameworks/MyStaticLibrary/prebuilt/MyStaticLibrary.xcframework"),
            ]
        ),
    ]
)
