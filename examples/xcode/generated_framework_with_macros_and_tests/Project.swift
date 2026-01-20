import ProjectDescription

let project = Project(
    name: "FrameworkWithMacros",
    targets: [
        // The macro implementation (executable)
        .target(
            name: "MyMacros",
            destinations: .macOS,
            product: .macro,
            bundleId: "dev.tuist.MyMacros",
            sources: ["Macros/Sources/**"],
            dependencies: [
                .external(name: "SwiftSyntaxMacros"),
                .external(name: "SwiftCompilerPlugin"),
            ]
        ),

        // Testable wrapper for the macro (framework with same sources)
        .target(
            name: "MyMacros_Testable",
            destinations: [.iPhone, .mac],
            product: .staticFramework,
            bundleId: "dev.tuist.MyMacros.testable",
            sources: ["Macros/Sources/**"],
            dependencies: [
                .external(name: "SwiftSyntaxMacros"),
                .external(name: "SwiftCompilerPlugin"),
            ]
        ),

        // Tests for the macro
        .target(
            name: "MyMacrosTests",
            destinations: [.mac],
            product: .unitTests,
            bundleId: "dev.tuist.MyMacrosTests",
            sources: ["Macros/Tests/**"],
            dependencies: [
                .target(name: "MyMacros_Testable"),
                .external(name: "SwiftSyntaxMacrosTestSupport"),
            ]
        ),

        // A framework that uses the macro
        .target(
            name: "Framework",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.Framework",
            sources: ["Framework/Sources/**"],
            dependencies: [
                .target(name: "MyMacros"),
            ]
        ),
    ]
)
