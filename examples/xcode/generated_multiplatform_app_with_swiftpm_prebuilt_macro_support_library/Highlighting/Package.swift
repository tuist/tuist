// swift-tools-version: 6.2
import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "Highlighting",
    platforms: [.iOS(.v17), .macOS(.v14), .macCatalyst(.v17)],
    products: [
        .library(name: "Highlighting", targets: ["Highlighting"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "604.0.0"),
    ],
    targets: [
        // Both the macro and the apps' runtime code use `SyntaxHelpers`, so the package keeps source swift-syntax.
        .target(name: "Highlighting", dependencies: ["HighlightingMacros", "SyntaxHelpers"]),
        .macro(
            name: "HighlightingMacros",
            dependencies: [
                "SyntaxHelpers",
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            ]
        ),
        .target(name: "SyntaxHelpers", dependencies: [.product(name: "SwiftSyntax", package: "swift-syntax")]),
    ]
)
