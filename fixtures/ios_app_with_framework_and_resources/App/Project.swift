import ProjectDescription

let project = Project(
    name: "MainApp",
    targets: [
        Target(
            name: "App",
            platform: .iOS,
            product: .app,
            bundleId: "io.tuist.App",
            infoPlist: "Config/App-Info.plist",
            sources: "Sources/**",
            resources: [
                "Resources/**/*.png",
                "Resources/*.xcassets",
                "Resources/**/*.txt",
                "Resources/**/*.strings",
                "Resources/**/*.stringsdict",
                "Resources/**/*.plist",
                "Resources/**/*.otf",
                "Resources/resource_without_extension",
                .glob(pattern: "ODRResources/*.png", tags: ["tag1"]),
                .glob(pattern: "ODRResources/odr_text.txt", tags: ["tag2"]),
                .folderReference(path: "Examples"),
                .folderReference(path: "ODRExamples", tags: ["tag1", "tag2"]),
            ],
            dependencies: [
                .project(target: "Framework1", path: "../Framework1"),
                .project(target: "StaticFramework", path: "../StaticFramework"),
                .project(target: "StaticFrameworkResources", path: "../StaticFramework"),
                .project(target: "StaticFramework2", path: "../StaticFramework2"),
                .project(target: "StaticFramework3", path: "../StaticFramework3"),
                .project(target: "StaticFramework4", path: "../StaticFramework4"),
                .project(target: "StaticFramework5", path: "../StaticFramework5"),
            ]
        ),
        Target(
            name: "AppTests",
            platform: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.AppTests",
            infoPlist: "Config/AppTests-Info.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "App"),
            ]
        ),
    ]
)
