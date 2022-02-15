import ProjectDescription

let project = Project(
    name: "FeatureOne",
    targets: [
        Target(
            name: "FeatureOneFramework",
            platform: .iOS,
            product: .framework,
            bundleId: "io.tuist.featureOne",
            sources: ["Sources/**"],
            dependencies: [
                .external(name: "Alamofire"),
            ]
        ),
    ]
)
