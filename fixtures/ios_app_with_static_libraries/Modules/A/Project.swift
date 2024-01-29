import ProjectDescription

let project = Project(
    name: "A",
    targets: [
        .target(
            name: "A",
            destinations: .iOS,
            product: .staticLibrary,
            bundleId: "io.tuist.A",
            infoPlist: nil,
            sources: "Sources/**",
            dependencies: [
                .project(target: "B", path: "../B"),
                .library(
                    path: "../C/prebuilt/C/libC.a",
                    publicHeaders: "../C/prebuilt/C",
                    swiftModuleMap: "../C/prebuilt/C/C.swiftmodule"
                ),
            ],

            settings: .settings(base: ["HEADER_SEARCH_PATHS": "$(SRCROOT)/CustomHeaders"])
        ),
        .target(
            name: "ATests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.ATests",
            infoPlist: nil,
            sources: "Tests/**",
            dependencies: [
                .target(name: "A"),
            ]
        ),
    ]
)
