import ProjectDescription

let project = Project(
    name: "App",
    organizationName: "Tuist",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.App",
            infoPlist: .default,
            sources: [
                "App/Sources/**",
                .generated("App/Generated/GeneratedEmptyFile.swift"),
                .generated("$(BUILT_PRODUCTS_DIR)/GeneratedEmptyFile2.swift"),
            ],
            scripts: [
                .pre(
                    path: "App/Scripts/generate_empty_file.sh",
                    name: "Generate empty file in directory",
                    outputPaths: ["$(SRCROOT)/App/Generated/GeneratedEmptyFile.swift"]
                ),
                .pre(
                    path: "App/Scripts/generate_empty_file.sh",
                    name: "Generated in directory",
                    outputPaths: ["$(BUILT_PRODUCTS_DIR)/GeneratedEmptyFile2.swift"]
                ),
            ]
        ),
    ]
)
