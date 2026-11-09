// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "TraitSettings",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TraitSettings", targets: ["TraitSettings"]),
    ],
    traits: [
        .default(enabledTraits: ["Enabled"]),
        .trait(name: "Enabled"),
        .trait(name: "Disabled"),
    ],
    targets: [
        .target(
            name: "TraitSettingsC",
            cSettings: [
                .define("ENABLED_TRAIT_C_DEFINE", .when(traits: ["Enabled"])),
                .define("MACOS_ENABLED_TRAIT_C_DEFINE", .when(platforms: [.macOS], traits: ["Enabled"])),
                .define("DISABLED_TRAIT_C_DEFINE", .when(traits: ["Disabled"])),
            ]
        ),
        .target(
            name: "TraitSettings",
            dependencies: ["TraitSettingsC"],
            swiftSettings: [
                .define("ENABLED_TRAIT_SWIFT_DEFINE", .when(traits: ["Enabled"])),
                .define("DISABLED_TRAIT_SWIFT_DEFINE", .when(traits: ["Disabled"])),
            ]
        ),
    ]
)
