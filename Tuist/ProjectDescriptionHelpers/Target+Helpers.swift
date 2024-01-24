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
        settings _: Settings = .settings(
            configurations: [
                .debug(name: "Debug", settings: [:], xcconfig: nil),
                .release(name: "Release", settings: [:], xcconfig: nil),
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
        return Target(
            name: name,
            destinations: [.mac],
            product: product,
            bundleId: "io.tuist.\(name)",
            deploymentTargets: .macOS("12.0"),
            infoPlist: .default,
            sources: ["\(rootFolder)/\(name)/**/*.swift"],
            dependencies: dependencies
        )
    }

    public static func module(
        name: String,
        product: Product = .staticFramework,
        hasTests: Bool = true,
        hasTesting: Bool = true,
        hasIntegrationTests: Bool = false,
        dependencies: [TargetDependency] = [],
        testDependencies: [TargetDependency] = [],
        testingDependencies: [TargetDependency] = [],
        integrationTestsDependencies: [TargetDependency] = []
    ) -> [Target] {
        var targets: [Target] = [
            .target(
                name: name,
                product: product,
                dependencies: dependencies
            ),
        ]
        var testTargets: [Target] = []
        if hasTests {
            testTargets.append(
                .target(
                    name: "\(name)Tests",
                    product: .unitTests,
                    dependencies: testDependencies + [
                        .target(name: name),
                        .external(name: "SwiftToolsSupport"),
                        .external(name: "SystemPackage"),
                    ]
                        + (hasTesting ? [.target(name: "\(name)Testing")] : [])
                )
            )
        }

        if hasTesting {
            targets.append(
                .target(
                    name: "\(name)Testing",
                    product: product,
                    dependencies: testingDependencies + [
                        .target(name: name),
                        .external(name: "SwiftToolsSupport"),
                        .external(name: "SystemPackage"),
                        .sdk(name: "XCTest", type: .framework, status: .optional),
                    ]
                )
            )
        }

        if hasIntegrationTests {
            testTargets.append(
                .target(
                    name: "\(name)IntegrationTests",
                    product: .unitTests,
                    dependencies: integrationTestsDependencies + [
                        .target(name: name),
                        .external(name: "SwiftToolsSupport"),
                        .external(name: "SystemPackage"),
                    ]
                        + (hasTesting ? [.target(name: "\(name)Testing")] : [])
                )
            )
        }

        return targets + testTargets
    }
}
