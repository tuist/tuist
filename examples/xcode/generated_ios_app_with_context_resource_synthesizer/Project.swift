import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.app",
            infoPlist: .default,
            sources: ["App/Sources/**"],
            resources: ["App/Resources/**"]
        ),
    ],
    // The "accessModifier" key is available in the Stencil template as {{param.accessModifier}}.
    // It overrides the default `publicAccess` param, so synthesized accessors use `internal` instead of `public`.
    resourceSynthesizers: [
        .files(
            extensions: ["json"],
            context: ["accessModifier": "internal"]
        ),
    ]
)
