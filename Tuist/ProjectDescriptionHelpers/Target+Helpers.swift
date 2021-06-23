import ProjectDescription

extension Target {
    /// - Parameters:
    ///     - dependencies: Dependencies for the main target.
    ///     - testDependencies: Dependencies for tests.
    ///     - testingDependencies: Dependencies for the testing target.
    public static func module(
        name: String,
        hasTests: Bool = true,
        hasTesting: Bool = true,
        product: Product = .dynamicLibrary,
        dependencies: [TargetDependency] = [],
        testDependencies: [TargetDependency] = [],
        testingDependencies: [TargetDependency] = []
    ) -> [Target] {
        var targets = [
            Target(
                name: "Tuist\(name)",
                platform: .macOS,
                product: product,
                bundleId: "io.tuist.Tuist\(name)",
                deploymentTarget: Constants.deploymentTarget,
                infoPlist: .default,
                sources: ["Sources/Tuist\(name)/**/*.swift"],
                dependencies: dependencies,
                settings: Settings(
                    configurations: [
                        .debug(name: "Debug", settings: [:], xcconfig: nil),
                        .release(name: "Release", settings: [:], xcconfig: nil),
                    ]
                )
            ),
        ]
        if hasTests {
            targets.append(
                Target(
                    name: "Tuist\(name)Tests",
                    platform: .macOS,
                    product: .unitTests,
                    bundleId: "io.tuist.Tuist\(name)Tests",
                    deploymentTarget: Constants.deploymentTarget,
                    infoPlist: .default,
                    sources: ["Tests/Tuist\(name)Tests/**/*.swift"],
                    dependencies: testDependencies + [
                        .target(name: "Tuist\(name)"),
                        .target(name: "Tuist\(name)Testing"),
                    ],
                    settings: Settings(
                        configurations: [
                            .debug(name: "Debug", settings: [:], xcconfig: nil),
                            .release(name: "Release", settings: [:], xcconfig: nil),
                        ]
                    )
                )
            )
        }
        
        if hasTesting {
            targets.append(
                Target(
                    name: "Tuist\(name)Testing",
                    platform: .macOS,
                    product: product,
                    bundleId: "io.tuist.Tuist\(name)Testing",
                    deploymentTarget: Constants.deploymentTarget,
                    infoPlist: .default,
                    sources: ["Sources/Tuist\(name)Testing/**/*.swift"],
                    dependencies: testingDependencies + [
                        .target(name: "Tuist\(name)"),
                        .sdk(name: "XCTest.framework", status: .optional)
                    ],
                    settings: Settings(
                        configurations: [
                            .debug(name: "Debug", settings: [:], xcconfig: nil),
                            .release(name: "Release", settings: [:], xcconfig: nil),
                        ]
                    )
                )
            )
        }
        
        return targets
    }
}
