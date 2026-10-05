import ProjectDescription

let project = Project(
    name: "Calculator",
    targets: [
        .target(
            name: "Calculator",
            destinations: .macOS,
            product: .framework,
            bundleId: "dev.tuist.Calculator",
            deploymentTargets: .macOS("14.0"),
            sources: ["Sources/Calculator/**"]
        ),
        .target(
            name: "CalculatorTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "dev.tuist.CalculatorTests",
            deploymentTargets: .macOS("14.0"),
            sources: ["Tests/CalculatorTests/**"],
            dependencies: [.target(name: "Calculator")]
        ),
        .target(
            name: "CalculatorSwiftTestingTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "dev.tuist.CalculatorSwiftTestingTests",
            deploymentTargets: .macOS("14.0"),
            sources: ["Tests/CalculatorSwiftTestingTests/**"],
            dependencies: [.target(name: "Calculator")]
        ),
    ],
    schemes: [
        .scheme(
            name: "Calculator",
            buildAction: .buildAction(targets: ["Calculator"]),
            testAction: .targets(["CalculatorTests", "CalculatorSwiftTestingTests"], options: .options(coverage: true))
        ),
    ]
)
