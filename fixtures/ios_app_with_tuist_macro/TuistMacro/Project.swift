import ProjectDescription

let project = Project(
    name: "TuistMacro",
    targets: [
        .target(
            name: "TuistMacro",
			destinations: .macOS,
			product: .macro,
			productName: "TuistMacro",
            bundleId: "io.tuist.TuistMacro",
			deploymentTargets: .macOS("14.0"),
			sources: ["TuistMacro/Sources/**"],
            dependencies: [
                            .external(name: "SwiftSyntaxMacros"),
                            .external(name: "SwiftCompilerPlugin"),
                        ]
        ),
        .target(
            name: "TuistMacroTests",
			destinations: [.iPhone, .iPad, .mac],
			product: .unitTests,
            bundleId: "io.tuist.TuistMacroTests",
            infoPlist: .default,
            sources: ["TuistMacro/Tests/**"],
            resources: [],
            dependencies: [
				.target(name: "TuistMacro"),
				.external(name: "SwiftSyntaxMacrosTestSupport")
			]
        ),
    ]
)
