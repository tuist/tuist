import ProjectDescription

let project = Project(
    name: "SampleMacro",
    packages: [
        .package(url: "https://github.com/apple/swift-syntax.git", from: "509.0.0"),
    ],
    targets: [
        .target(
            name: "CommandLineTool",
            destinations: .macOS,
            product: .commandLineTool,
            bundleId: "com.example.cli",
            sources: ["CommandLineTool/Sources/**"],
            dependencies: [
                .macro(name: "SampleMacro"),
            ]
        ),
//        .target(
//          name: "ExtenalSampleMacro",
//          destinations: .macOS,
//          product: .framework,
//          bundleId: "com.example.samplemacro",
//          sources: ["Modules/SampleMacro/Sources/SampleMacro/**"],
//          dependencies: [
//            .external(name: "SwiftSyntaxMacros"),
//            .external(name: "SwiftCompilerPlugin"),
//          ]
//        )
        .target(
            name: "SampleMacro",
            destinations: .macOS,
            product: .framework,
            bundleId: "com.example.samplemacro",
            sources: ["Modules/SampleMacro/Sources/SampleMacro/**"],
            dependencies: [
                .macro(name: "SampleMacroPlugin"),
            ]
        ),
        .target(
            name: "SampleMacroPlugin",
            destinations: .macOS,
            product: .macro,
            bundleId: "com.example.samplemacroplugin",
            sources: ["Modules/SampleMacro/Sources/SampleMacroPlugin/**"],
            dependencies: [
                //                .external(name: "SwiftSyntaxMacros"),
//                .external(name: "SwiftCompilerPlugin"),
                .package(product: "SwiftSyntaxMacros", type: .runtime),
                .package(product: "SwiftCompilerPlugin", type: .runtime),
            ]
        ),
    ]
)
