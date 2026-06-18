// swift-tools-version: 5.9
@preconcurrency import PackageDescription

#if TUIST
import ProjectDescription

// swiftlint:disable:next prefixed_toplevel_constant
let packageSettings = PackageSettings(
    // Customize the product types for specific package product
    // Default is .staticFramework
    // productTypes: ["Alamofire": .framework,]
    productTypes: [:],
    baseSettings: .settings(configurations: [
        // Note: We have to provide these 3 configurations to the package dependencies so
        // that they align the same with the Project and Target configurations. We don't provide
        // any actual settings changes, just the names stay the same.
        .debug(name: "Debug"),
        .release(name: "Release"),
        .release(name: "InHouse")
    ])
)
#endif // TUIST

// swiftlint:disable:next prefixed_toplevel_constant
let package = Package(
    name: "ExternalDependencies",
    dependencies: [
        // Github (modmed)

        // ....

        // Github (modmed-public)
        .package(url: "git@github.com:modmed-public/CLTokenInputView.git", revision: "0092aaa65a6a766fd456613efb2c0f13eb01113c"),
        .package(url: "git@github.com:modmed-public/TPKeyboardAvoiding.git", revision: "1f44bf6f72ae14453187c91708390a92b15d388b"),
        .package(url: "git@github.com:modmed-public/SVProgressHUD.git", exact: "4.1.0"),
        .package(url: "git@github.com:modmed-public/TSMessages.git", revision: "aecac0baa900a9d440fc12f383194f52b4637d8f"),
        // Github
        .package(url: "git@github.com:aws-amplify/aws-sdk-ios-spm", exact: "2.36.3"),
        .package(url: "git@github.com:apple/swift-collections.git", exact: "1.3.0"),
        .package(url: "git@github.com:urbanairship/ios-library.git", exact: "19.11.8"),
        .package(url: "git@github.com:abbiio/iosdk", exact: "2.20.4"),
        .package(url: "git@github.com:bugsnag/bugsnag-cocoa.git", exact: "6.28.1"),
        .package(url: "git@github.com:hmlongco/Factory.git", exact: "2.3.2"),
        .package(url: "git@github.com:Datadog/dd-sdk-ios.git", exact: "3.3.0")
        // Dragon has a compiler error when Tuist tries to turn it into an XCFramework for cache. Revisit later.
        // .package(url: "git@github.com:nuance-communications/Dragon-Medical-SpeechKit-iOS", exact: "6.2.2")
    ]
)
