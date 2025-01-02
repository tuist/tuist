import ProjectDescription

let project = Project(
	name: "TuistMacro",
	targets: [
		.target(
			name: "TuistMacro",
			destinations: .macOS,
			product: .macro,
			bundleId: "io.tuist.TuistMacro",
			deploymentTargets: .macOS("14.0"),
			sources: ["TuistMacro/Sources/**"],
			dependencies: [
				.external(name: "SwiftSyntaxMacros"),
				.external(name: "SwiftCompilerPlugin"),
			]
		),
		.target(
			name: "TuistMacro_Testable",
			destinations: [.iPhone, .iPad, .mac],
			product: .framework,
			bundleId: "io.tuist.TuistMacro.Testable",
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
				.target(name: "TuistMacro_Testable"),
				.external(name: "SwiftSyntaxMacrosTestSupport"),
			]
		),
	]
)
