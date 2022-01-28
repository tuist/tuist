import ProjectDescription

let project = Project(
    name: "DocC",
    organizationName: "tuist.io",
    targets: [
        Target(
            name: "SlothCreator",
            platform: .iOS,
            product: .framework,
            bundleId: "io.tuist.framework",
            deploymentTarget: .iOS(targetVersion: "13.0", devices: .iphone),
            infoPlist: .default,
            sources: ["Targets/SlothCreator/Sources/**"]
        ),
    ]
)
