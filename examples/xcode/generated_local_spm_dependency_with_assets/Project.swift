import ProjectDescription

let project = Project(
    name: "TuistSampleProject",
    targets: [
        .target(
            name: "TuistSampleProject",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.TuistSampleProject",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ],
                ]
            ),
            sources: ["TuistSampleProject/Sources/**"],
            resources: ["TuistSampleProject/Resources/**"],
            dependencies: [
                .external(name: "DependencyWithImages")
            ]
        ),
        .target(
            name: "TuistSampleProjectTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.TuistSampleProjectTests",
            infoPlist: .default,
            sources: ["TuistSampleProject/Tests/**"],
            resources: [],
            dependencies: [.target(name: "TuistSampleProject")]
        ),
    ]
)
