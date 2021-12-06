import ProjectDescription

let project = Project(
    name: "AppTestsSupport",
    targets: [
        Target(
            name: "AppTestsSupport",
            platform: .iOS,
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
