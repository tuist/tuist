import ProjectDescription

let project = Project(
    name: "Prebuilt",
    targets: [
        .target(
            name: "PrebuiltStaticFramework",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "io.tuist.PrebuiltStaticFramework",
            infoPlist: "Config/Info.plist",
            sources: "Sources/**",
            dependencies: [],
            settings: .settings(base: ["BUILD_LIBRARY_FOR_DISTRIBUTION": "YES"])
        ),
    ]
)
