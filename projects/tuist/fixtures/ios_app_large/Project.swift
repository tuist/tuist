import ProjectDescription

func target(name: String) -> Target {
    Target(
        name: name,
        platform: .iOS,
        product: .app,
        bundleId: "io.tuist.\(name)",
        infoPlist: .file(path: .relativeToManifest("Info.plist")),
        sources: .paths([.relativeToManifest("Sources/**")]),
        settings: .settings(base: ["CODE_SIGN_IDENTITY": "", "CODE_SIGNING_REQUIRED": "NO"])
    )
}

let project = Project(
    name: "App",
    targets: (1 ... 300).map { target(name: "App\($0)") }
)
