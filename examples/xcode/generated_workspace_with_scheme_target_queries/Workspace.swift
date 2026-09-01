import ProjectDescription

let workspace = Workspace(
    name: "Modules",
    projects: [
        "Features/*",
        "Frameworks/*",
    ],
    schemes: [
        .scheme(
            name: "AllUnitTests",
            testAction: .targets(
                matching: ["*-UnitTests"],
                options: .options(coverage: true)
            )
        ),
        .scheme(
            name: "AllScreenshotTests",
            testAction: .targets(
                matching: ["tag:screenshot-tests"],
                options: .options(coverage: false)
            )
        ),
        .scheme(
            name: "AllFrameworks",
            buildAction: .buildAction(matching: ["HomeFeature", "*Kit"])
        ),
    ]
)
