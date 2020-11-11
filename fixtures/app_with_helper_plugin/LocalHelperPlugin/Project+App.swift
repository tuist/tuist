import ProjectDescription

extension Project {

    public static func app(name: String, platform: Platform) -> Project {
        Project(
            name: name,
            organizationName: "tuist.io",
            targets: [
                .init(
                    name: name,
                    platform: platform,
                    product: .app,
                    bundleId: "io.tuist.App",
                    infoPlist: .default,
                    sources: ["Sources/**/*.swift"]
                )
            ]
        )
    }
}
