import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
    name: "FeatureOne",
    settings: .projectSettings,
    targets: [
        Target(
            name: "FeatureOneFramework_iOS",
            platform: .iOS,
            product: .framework,
            bundleId: "io.tuist.featureOne",
            sources: ["Sources/**"],
            settings: .targetSettings
        ),
        Target(
            name: "FeatureOneFramework_watchOS",
            platform: .watchOS,
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
