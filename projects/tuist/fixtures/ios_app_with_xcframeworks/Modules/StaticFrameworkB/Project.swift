import ProjectDescription

let project = Project(
    name: "StaticFrameworkB",
    targets: [
        Target(
            name: "StaticFrameworkB",
            platform: .iOS,
            product: .staticFramework,
            bundleId: "io.tuist.StaticFrameworkB",
            infoPlist: .default,
            sources: ["Sources/**"],
            dependencies: [
                .xcframework(path: "../../XCFrameworks/MyStaticLibrary/prebuilt/MyStaticLibrary.xcframework"),
            ]
        ),
    ]
)
