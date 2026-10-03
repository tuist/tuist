import ProjectDescription

let scope = Environment.consumerScope.getString(default: "combined")
let artifactDirectory = Environment.artifactDirectory.getString(default: "")
let dependencies: [TargetDependency] = artifactDirectory.isEmpty
    ? [.external(name: "Shared")]
    : ["Shared", "Leaf"].map {
        .xcframework(path: .path("\(artifactDirectory)/\($0).xcframework"))
    }

let project = Project(
    name: "PlatformNarrowing",
    settings: .settings(base: ["CODE_SIGNING_ALLOWED": "NO"]),
    targets: [
        scope != "macos" ? .target(
            name: "PhoneConsumer",
            destinations: [.iPhone, .iPad, .macWithiPadDesign],
            product: .framework,
            bundleId: "dev.tuist.reproduction.phone",
            deploymentTargets: .iOS("16.0"),
            infoPlist: .default,
            sources: ["Consumers/Phone.swift"],
            dependencies: dependencies
        ) : nil,
        scope != "ios" ? .target(
            name: "MacConsumer",
            destinations: [.mac],
            product: .commandLineTool,
            bundleId: "dev.tuist.reproduction.mac",
            deploymentTargets: .macOS("13.0"),
            sources: ["Consumers/main.swift"],
            dependencies: dependencies
        ) : nil,
    ].compactMap { $0 }
)
