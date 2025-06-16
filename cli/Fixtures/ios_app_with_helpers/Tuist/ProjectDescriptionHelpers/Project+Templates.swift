import ProjectDescription

extension Project {
    public static func app(name: String, destinations: Destinations, dependencies: [TargetDependency] = []) -> Project {
        project(name: name, product: .app, destinations: destinations, dependencies: dependencies, infoPlist: [
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
        ])
    }

    public static func framework(name: String, destinations: Destinations, dependencies: [TargetDependency] = []) -> Project {
        project(name: name, product: .framework, destinations: destinations, dependencies: dependencies)
    }

    public static func project(
        name: String,
        product: Product,
        destinations: Destinations,
        dependencies: [TargetDependency] = [],
        infoPlist: [String: Plist.Value] = [:]
    ) -> Project {
        Project(
            name: name,
            targets: [
                .target(
                    name: name,
                    destinations: destinations,
                    product: product,
                    bundleId: "io.tuist.\(name)",
                    infoPlist: .extendingDefault(with: infoPlist),
                    sources: ["Sources/**"],
                    resources: [],
                    dependencies: dependencies
                ),
                .target(
                    name: "\(name)Tests",
                    destinations: destinations,
                    product: .unitTests,
                    bundleId: "io.tuist.\(name)Tests",
                    infoPlist: .default,
                    sources: "Tests/**",
                    dependencies: [
                        .target(name: "\(name)"),
                    ]
                ),
            ]
        )
    }
}
