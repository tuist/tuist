import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: [.mac],
            product: .app,
            bundleId: "dev.tuist.App",
            infoPlist: .file(path: .relativeToManifest("Info.plist")),
            sources: .paths([.relativeToManifest("Sources/**")]),
            copyFiles: [
                .sharedSupport(
                    name: "Copy Templates",
                    subpath: "Templates",
                    files: [.glob(pattern: "Templates/**", condition: .when([.macos]))]
                ),
                .wrapper(
                    name: "Embed Login Items",
                    subpath: "Contents/Library/LoginItems",
                    files: [.buildProduct(name: "LoginItemHelper", codeSignOnCopy: true)]
                ),
            ],
            dependencies: [
                .target(name: "LoginItemHelper"),
            ],
            settings: .settings(base: ["CODE_SIGN_IDENTITY": "", "CODE_SIGNING_REQUIRED": "NO"])
        ),
        .target(
            name: "LoginItemHelper",
            destinations: [.mac],
            product: .app,
            bundleId: "dev.tuist.App.LoginItemHelper",
            infoPlist: .file(path: .relativeToManifest("LoginItemHelper/Info.plist")),
            sources: .paths([.relativeToManifest("LoginItemHelper/Sources/**")]),
            settings: .settings(base: ["CODE_SIGN_IDENTITY": "", "CODE_SIGNING_REQUIRED": "NO"])
        ),
    ]
)
