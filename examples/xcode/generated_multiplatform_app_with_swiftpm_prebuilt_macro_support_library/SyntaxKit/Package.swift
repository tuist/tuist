// swift-tools-version: 6.2
import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "SyntaxKit",
    platforms: [.iOS(.v17), .macOS(.v14), .macCatalyst(.v17)],
    products: [
        .library(name: "Formatting", targets: ["Formatting"]),
        // Like swift-case-paths' `CasePathsMacrosSupport`: a library product that only macros use.
        .library(name: "FormattingMacrosSupport", targets: ["FormattingMacrosSupport"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "604.0.0"),
    ],
    targets: [
        .target(name: "Formatting", dependencies: ["FormattingMacros"]),
        // The macro only reaches swift-syntax through its support library.
        .macro(name: "FormattingMacros", dependencies: ["FormattingMacrosSupport"]),
        .target(
            name: "FormattingMacrosSupport",
            dependencies: [
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            ]
        ),
    ]
)
