import ProjectDescription

let project = Project(
    name: "TuistCacheIssue",
    targets: [
        .target(
            name: "TuistCacheIssue",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.TuistCacheIssue",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ],
                ]
            ),
            sources: ["TuistCacheIssue/Sources/**"],
            resources: ["TuistCacheIssue/Resources/**"],
            dependencies: []
        ),
        .target(
            name: "TuistCacheIssueTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.TuistCacheIssueTests",
            infoPlist: .default,
            sources: ["TuistCacheIssue/Tests/**"],
            resources: [],
            dependencies: [
                .target(name: "TuistCacheIssue"),
                .external(name: "Nimble"),
            ]
        ),
    ]
)
