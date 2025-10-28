// Created 09/01/2025

import ProjectDescription

let project = Project(
	name: "App",
	targets: [
		.target(
			name: "App",
			destinations: [.iPhone],
			product: .app,
			bundleId: "io.tuist.fixtures.app",
			infoPlist: .default,
			buildableFolders: [
				"App/Sources",
				"App/Resources",
			],
			dependencies: []
		),
	]
)
