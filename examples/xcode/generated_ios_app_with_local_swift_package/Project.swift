import ProjectDescription

let project = Project(
    name: "App",
    packages: [
        .package(path: "Packages/PackageA"),
    ],
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.App",
            infoPlist: "Support/Info.plist",
            sources: ["Sources/**"],
            resources: [
                // Path to resources can be defined here
                // "Resources/**"
            ],
            dependencies: [
                .project(target: "FrameworkA", path: "Frameworks/FrameworkA"),
                .package(product: "LibraryA"),
                .package(product: "LibraryB"),
                .package(product: "LibraryC"),
            ]
        ),
        .target(
            name: "AppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.AppTests",
            infoPlist: "Support/Tests.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "App"),
            ]
        ),
    ],
    schemes: [
        .scheme(
            name: "AppWithPackageCoverage",
            buildAction: .buildAction(targets: ["App"]),
            testAction: .targets(
                ["AppTests"],
                options: .options(
                    coverage: true,
                    codeCoverageTargets: [
                        // Valid: the name of a package product consumed by the App target.
                        .project(path: "Packages/PackageA", target: "LibraryC"),
                        // Invalid: the name of the package target backing the product.
                        // It is not a coverage buildable, so it is dropped with a warning.
                        .project(path: "Packages/PackageA", target: "LibraryCCore"),
                    ]
                )
            )
        ),
    ]
)
