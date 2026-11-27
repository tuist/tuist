import ProjectDescription

let project = Project(
	name: "ios_app_with_tuist_macro",
	targets: [
		// MARK: App Target + Tests
		.target(
			name: "ios_app_with_tuist_macro",
			destinations: .iOS,
			product: .app,
			bundleId: "io.tuist.ios-app-with-tuist-macro",
			infoPlist: .extendingDefault(
				with: [
					"UILaunchScreen": [
						"UIColorName": "",
						"UIImageName": "",
					],
				]
			),
			sources: ["ios_app_with_tuist_macro/Sources/**"],
			resources: ["ios_app_with_tuist_macro/Resources/**"],
			dependencies: [
				.target(name: "TuistMacro"),
			]
		),
		.target(
			name: "ios_app_with_tuist_macroTests",
			destinations: .iOS,
			product: .unitTests,
			bundleId: "io.tuist.ios-app-with-tuist-macroTests",
			sources: ["ios_app_with_tuist_macro/Tests/**"],
			dependencies: [
				.target(name: "ios_app_with_tuist_macro"),
			]
		),
		
		// MARK: Macro Targets + Tests
		.target(
			name: "TuistMacroMacros",
			destinations: .macOS,
			product: .macro,
			bundleId: "io.tuist.TuistMacroMacros",
			deploymentTargets: .macOS("14.0"),
			sources: ["TuistMacro/Sources/TuistMacroMacros/**"],
			dependencies: [
				.external(name: "SwiftSyntaxMacros"),
				.external(name: "SwiftCompilerPlugin"),
			]
		),
		.target(
			name: "TuistMacro",
			destinations: [.iPhone, .iPad, .mac],
			product: .framework,
			bundleId: "io.tuist.TuistMacro",
			sources: ["TuistMacro/Sources/TuistMacro/**"],
			dependencies: [
				.target(name: "TuistMacroMacros"),
			]
		),
		.target(
			name: "TuistMacroClient",
			destinations: .macOS,
			product: .commandLineTool,
			bundleId: "io.tuist.TuistMacroClient",
			sources: ["TuistMacro/Sources/TuistMacroClient/**"],
			dependencies: [
				.target(name: "TuistMacro"),
			]
		),
		.target(
			name: "TuistMacroTests",
			destinations: .macOS,
			product: .unitTests,
			bundleId: "io.tuist.TuistMacroTests",
			deploymentTargets: .macOS("14.0"),
			infoPlist: .default,
			sources: ["TuistMacro/Tests/**"],
			dependencies: [
				.target(name: "TuistMacroMacros"),
				.external(name: "SwiftSyntaxMacrosTestSupport"),
			]
		),
	]
)
