import ProjectDescription

func target(name: String) -> Target {
    print("Target name - \(name)")
    return Target(
        name: name,
        platform: .macOS,
        product: .app,
        bundleId: "io.tuist.\(name)",
        infoPlist: .default,
        sources: .paths([.relativeToManifest("Sources/**")]),
        settings: .settings(base: ["CODE_SIGN_IDENTITY": "", "CODE_SIGNING_REQUIRED": "NO"])
    )
}

let project = Project(
    name: "App",
    targets: [target(name: "App")]
)
