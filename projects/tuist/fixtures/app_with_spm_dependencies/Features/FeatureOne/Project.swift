import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
    name: "FeatureOne",
    settings: .projectSettings,
    targets: [
        Target(
            name: "FeatureOneFramework",
            platform: .iOS,
            product: .framework,
            bundleId: "io.tuist.featureOne",
            sources: ["Sources/**"],
            dependencies: [
                .external(name: "Alamofire"),
            ],
            settings: .targetSettings
        ),
    ],
    schemes: Scheme.allSchemes(for: ["FeatureOneFramework"])
)
