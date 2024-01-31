import ProjectDescription

let project = Project(
    name: "AppTestsSupport",
    targets: [
        .target(
            name: "AppTestsSupport",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "io.tuist.AppTestsSupport",
            infoPlist: "Info.plist",
            sources: "Sources/**",
            dependencies: [
                .framework(path: "../../Prebuilt/prebuilt/PrebuiltStaticFramework.framework"),
            ]
        ),
    ]
)
