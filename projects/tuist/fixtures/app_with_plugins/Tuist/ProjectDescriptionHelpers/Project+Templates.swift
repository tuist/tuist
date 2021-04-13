import ProjectDescription

extension Project {
    /// Helper function to create the Project for this ExampleApp
    public static func app(name: String, platform: Platform, additionalTargets: [String]) -> Project {
        let mainTarget = Target(
            name: name,
            platform: platform,
            product: .app,
            bundleId: "io.tuist.\(name)",
            infoPlist: .default,
            sources: ["Source/**"],
            resources: [
                "Resources/**",
            ],
            dependencies: []
        )
        
        return Project(
            name: name,
            organizationName: "tuist.io",
            targets: [mainTarget],
            resourceSynthesizers: [
                .strings(plugin: "LocalPlugin"),
                .custom(
                    name: "Lottie",
                    parser: .json,
                    extensions: ["lottie"]
                )
            ]
        )
    }
}
