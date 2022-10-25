import ProjectDescription

func target(name: String, platform: Platform, deploymentTargets: [DeploymentTarget]) -> Target {
    Target(
        name: name + platform.rawValue.capitalized,
        platform: platform,
        product: .app,
        bundleId: "io.tuist.\(name)",
        deploymentTargets: deploymentTargets,
        sources: .paths([.relativeToManifest("Sources/**")]),
        dependencies: [.target(name: "MultiTargetsFramework")],
        settings: .settings(base: ["CODE_SIGN_IDENTITY": "", "CODE_SIGNING_REQUIRED": "NO"])
    )
}

func framework(name: String, deploymentTargets: [DeploymentTarget]) -> Target {
    Target(
        name: name,
        platform: .iOS,
        product: .framework,
        bundleId: "io.tuist.\(name)",
        deploymentTargets: deploymentTargets,
        sources: .paths([.relativeToManifest("Framework/Sources/**")]),
        dependencies: [.zipFoundation],
        settings: .settings(base: ["CODE_SIGN_IDENTITY": "", "CODE_SIGNING_REQUIRED": "NO"])
    )
}

func tests(name: String, platform: Platform, deploymentTargets: [DeploymentTarget]) -> Target {
    Target(
        name: name + platform.rawValue.capitalized + "Tests",
        platform: platform,
        product: .unitTests,
        bundleId: "io.tuist.\(name)",
        deploymentTargets: deploymentTargets,
        infoPlist: .file(path: .relativeToManifest("Info.plist")),
        sources: .paths([.relativeToManifest("Tests/**")]),
        dependencies: [.target(name: name + platform.rawValue.capitalized), .quick, .nimble],
        settings: .settings(base: ["CODE_SIGN_IDENTITY": "", "CODE_SIGNING_REQUIRED": "NO"])
    )
}

let project = Project(
    name: "MyApp",
    targets: [
        target(
            name: Constants.singlePlatformAppName,
            platform: .iOS,
            deploymentTargets: [.iOS(targetVersion: "16.0", devices: [.ipad, .iphone])]
        ),
        target(
            name: Constants.singlePlatformAppName,
            platform: .macOS,
            deploymentTargets: [.macOS(targetVersion: "13.0")]
        ),
        target(
            name: Constants.singlePlatformAppName,
            platform: .tvOS,
            deploymentTargets: [.tvOS(targetVersion: "16.0")]
        ),
        framework(
            name: Constants.multiTargetsFrameworkName,
            deploymentTargets: [
                .iOS(targetVersion: "16.0", devices: [.ipad, .iphone]),
                .macOS(targetVersion: "13.0"),
                .tvOS(targetVersion: "16.0"),
            ]
        ),
        target(
            name: Constants.multiplePlatformAppName,
            platform: .iOS,
            deploymentTargets: [
                .iOS(targetVersion: "16.0", devices: [.ipad, .iphone]),
                .macOS(targetVersion: "13.0"),
                .tvOS(targetVersion: "16.0"),
            ]
        ),
        tests(
            name: Constants.multiplePlatformAppName,
            platform: .iOS,
            deploymentTargets: [
                .iOS(targetVersion: "16.0", devices: [.ipad, .iphone]),
                .macOS(targetVersion: "13.0"),
                .tvOS(targetVersion: "16.0"),
            ]
        ),
    ]
)

enum Constants {
    static let singlePlatformAppName = "TuistMultipleDeploymentTargetsFrameworkExample"
    static let multiplePlatformAppName = "TuistMultipleDeploymentTargetsAppExample"
    static let multiTargetsFrameworkName = "MultiTargetsFramework"
}

extension TargetDependency {
    public static var zipFoundation: TargetDependency {
        .external(name: "ZIPFoundation")
    }

    public static var quick: TargetDependency {
        .external(name: "Quick")
    }

    public static var nimble: TargetDependency {
        .external(name: "Nimble")
    }
}
