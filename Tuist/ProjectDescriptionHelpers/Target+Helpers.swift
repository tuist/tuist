import ProjectDescription

public enum TargetType {
    case tests
    case sources
}

extension Target {
    public static func target(
        name: String,
        product: Product,
        dependencies: [TargetDependency]
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
            platform: .macOS,
            product: product,
            bundleId: "io.tuist.\(name)",
            deploymentTarget: Constants.deploymentTarget,
            infoPlist: .default,
            sources: ["\(rootFolder)/\(name)/**/*.swift"],
            dependencies: dependencies,
            settings: .settings(
                configurations: [
                    .debug(name: "Debug", settings: [:], xcconfig: nil),
                    .release(name: "Release", settings: [:], xcconfig: nil),
                ]
            )
        )
    }

    /// - Parameters:
    ///     - dependencies: Dependencies for the main target.
    ///     - testDependencies: Dependencies for tests.
    ///     - testingDependencies: Dependencies for the testing target.
    ///     - integrationTestsDependencies: Dependencies for the integration tests.
    public static func module(
        name: String,
        product: Product = .framework,
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
                    ]
                        + (hasTesting ? [.target(name: "\(name)Testing")] : [])
                )
            )
        }

        return targets + testTargets
    }
}
