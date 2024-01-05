import ProjectDescription
import ProjectDescriptionHelpers

let supportedPlatforms: Set<Platform> = [.iOS]

let project = Project(
    name: "ModuleA",
    targets: [
        Target(
            name: "ModuleAInterface",
            destinations: .destinations(for:supportedPlatforms),
            product: .framework,
            bundleId: "io.tuist.ModuleA.interface",
            deploymentTargets: .deploymentTargets(for: supportedPlatforms),
            sources: [
                .glob("Implementation/Sources/**"),
            ]
        ),
        Target(
            name: "ModuleAImplementation",
            destinations: .destinations(for:supportedPlatforms),
            product: .framework,
            bundleId: "io.tuist.ModuleA.implementation",
            deploymentTargets: .deploymentTargets(for: supportedPlatforms),
            sources: [
                .glob("Implementation/Sources/**"),
            ],
            dependencies: [
                .target(name: "ModuleAInterface"),
            ]
        ),
        Target(
            name: "ModuleATestSupporting",
            destinations: .destinations(for:supportedPlatforms),
            product: .framework,
            bundleId: "io.tuist.ModuleA.testSupporting",
            deploymentTargets: .deploymentTargets(for: supportedPlatforms),
            sources: [
                .glob("TestSupporting/Sources/**"),
            ],
            dependencies: [
                .target(name: "ModuleAInterface"),
                .external(name: "Mocker")
            ]
        ),
        Target(
            name: "ModuleATests",
            destinations: .destinations(for:supportedPlatforms),
            product: .unitTests,
            bundleId: "io.tuist.ModuleA.tests",
            deploymentTargets: .deploymentTargets(for: supportedPlatforms),
            sources: [
                .glob("Tests/Sources/**"),
            ],
            dependencies: [
                .target(name: "ModuleATestSupporting"),
                .xctest,
                .external(name: "Mocker")
            ]
        ),
        Target(
          name: "ExampleApp",
          destinations: .destinations(for: [.iOS]),
          product: .app,
          bundleId: "io.tuist.ModuleA.example",
          deploymentTargets: .deploymentTargets(for: [.iOS]),
          infoPlist: "Example/SupportingFiles/App-Info.plist",
          sources: "Example/Sources/**",
          dependencies: [
                .target(name: "ModuleAInterface"),
                .target(name: "ModuleAImplementation"),
                .target(name: "ModuleATestSupporting"),
          ]
      )
    ]
)
