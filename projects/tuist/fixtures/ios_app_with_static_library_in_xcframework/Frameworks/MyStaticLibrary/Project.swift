import ProjectDescription

let project = Project(
    name: "MyStaticLibrary",
    targets: [
        Target(
            name: "MyStaticLibrary",
            platform: .iOS,
            product: .staticLibrary,
            bundleId: "io.tuist.MyStaticLibrary",
            infoPlist: "Info.plist",
            sources: ["Sources/**"],
            resources: [
                /* Path to resources can be defined here */
                // "Resources/**"
            ],
            dependencies: [
                /* Target dependencies can be defined here */
                // .framework(path: "Frameworks/MyStaticLibrary.framework")
            ],
            settings: .settings(base: [
                "BUILD_LIBRARY_FOR_DISTRIBUTION": "YES",
            ])
        ),
    ]
)
