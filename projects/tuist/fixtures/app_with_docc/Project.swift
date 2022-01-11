import ProjectDescription

let project = Project(
    name: "App",
    organizationName: "tuist.io",
    targets: [
        Target(
            name: "App",
            platform: .iOS,
            product: .app,
            bundleId: "io.tuist.framework",
            deploymentTarget: .iOS(targetVersion: "13.0", devices: .iphone),
            infoPlist: .default,
            sources: ["Targets/App/Sources/**"],
            dependencies: [.project(target: "Framework", path: ".")]
        ),
        Target(
            name: "Framework",
            platform: .iOS,
            product: .framework,
            bundleId: "io.tuist.framework",
            deploymentTarget: .iOS(targetVersion: "13.0", devices: .iphone),
            infoPlist: .default,
            sources: [SourceFileGlob(
                "Targets/Framework/Sources/**",
                excluding: "Targets/Framework/Sources/ImportantDocumentation.docc/**/*.swift"
            )]
        ),
    ]
)
