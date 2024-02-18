import ProjectDescription

let frameworkType = Product.framework
let dependencies = Dependencies(
    swiftPackageManager: .init(
        productTypes: [
            "CasePaths": frameworkType,
            "SwiftBasicFormat": frameworkType,
            "SwiftCompilerPlugin": frameworkType,
            "SwiftCompilerPluginMessageHandling": frameworkType,
            "SwiftDiagnostics": frameworkType,
            "SwiftOperators": frameworkType,
            "SwiftParser": frameworkType,
            "SwiftParserDiagnostic": frameworkType,
            "SwiftSyntax": frameworkType,
            "SwiftSyntax509": frameworkType,
            "SwiftSyntaxBuilder": frameworkType,
            "SwiftSyntaxMacroExpansion": frameworkType,
            "SwiftSyntaxMacros": frameworkType,
            "XCTestDynamicOverlay": frameworkType,
        ],
        targetSettings: [:]
    ),
    platforms: [.macOS, .iOS]
)
