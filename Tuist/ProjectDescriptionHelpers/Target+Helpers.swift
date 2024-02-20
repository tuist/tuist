import ProjectDescription

public enum TargetType {
    case tests
    case sources
}

extension Target {
    public static func target(
        name: String,
        product: Product,
        dependencies: [TargetDependency],
        settings: Settings = .settings(
            configurations: [
                .debug(
                    name: "Debug",
                    settings: ["SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) MOCKING"],
                    xcconfig: nil
                ),
                .release(
                    name: "Release",

                    settings: [:],
                    xcconfig: nil
                ),
            ]
        )
    ) -> Target {
        let rootFolder: String
        switch product {
        case .unitTests:
            rootFolder = "Tests"
        default:
            rootFolder = "Sources"
        }
        return .target(
            name: name,
            destinations: [.mac],
            product: product,
            bundleId: "io.tuist.\(name)",
            deploymentTargets: .macOS("12.0"),
            infoPlist: .default,
            sources: ["\(rootFolder)/\(name)/**/*.swift"],
            dependencies: dependencies,
            settings: settings
        )
    }

    public static func module(
        name _: String,
        product _: Product = .staticFramework,
        hasTests _: Bool = true,
        hasTesting _: Bool = true,
        hasIntegrationTests _: Bool = false,
        dependencies _: [TargetDependency] = [],
        testDependencies _: [TargetDependency] = [],
        testingDependencies _: [TargetDependency] = [],
        integrationTestsDependencies _: [TargetDependency] = []
    ) -> [Target] {
        return []
    }
}
