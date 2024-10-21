import ProjectDescription

let project = Project(
    name: "AppWithOnDemandResources",
    targets: [
        .target(
            name: "AppWithOnDemandResources",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.AppWithOnDemandResources",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchStoryboardName": "LaunchScreen.storyboard",
                ]
            ),
            sources: ["AppWithOnDemandResources/Sources/**"],
            resources: [
                "AppWithOnDemandResources/Resources/**",
                .folderReference(path: "AppWithOnDemandResources/OnDemandResources", tags: ["datafolder"]),
                .glob(pattern: "AppWithOnDemandResources/on-demand-data.txt", tags: ["datafile"]),
            ],
            dependencies: [],
            onDemandResourcesTags: .tags(
                initialInstall: ["json", "data file"],
                prefetchOrder: ["image-stack", "image", "tag with space"]
            )
        ),
        .target(
            name: "AppWithOnDemandResourcesTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.AppWithOnDemandResourcesTests",
            infoPlist: .default,
            sources: ["AppWithOnDemandResources/Tests/**"],
            resources: [],
            dependencies: [.target(name: "AppWithOnDemandResources")]
        ),
    ]
)
