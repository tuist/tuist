import ProjectDescription

let project = Project(
    name: "StaticFrameworkA",
    targets: [
        Target(
            name: "StaticFrameworkA",
            platform: .iOS,
            product: .staticFramework,
            bundleId: "io.tuist.StaticFrameworkA",
            infoPlist: .default,
            sources: ["Sources/**"],
            dependencies: [
                .xcframework(path: "../../XCFrameworks/MyStaticLibrary/prebuilt/MyStaticLibrary.xcframework"),
            ]
        ),
    ]
)
