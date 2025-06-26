import ProjectDescription

let project = Project(
    name: "StaticFrameworkB",
    targets: [
        .target(
            name: "StaticFrameworkB",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "dev.tuist.StaticFrameworkB",
            infoPlist: .default,
            sources: ["Sources/**"],
            dependencies: [
                .xcframework(path: "../../XCFrameworks/MyStaticLibrary/prebuilt/MyStaticLibrary.xcframework"),
            ]
        ),
    ]
)
