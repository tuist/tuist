// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Dependencies",
    dependencies: [
        .package(id: "marmelroy.PhoneNumberKit", from: "4.2.13"),
        .package(id: "onfido.onfido-ios-sdk", from: "33.0.1"),
        .package(
            url: "https://github.com/FriendlyCaptcha/friendly-captcha-ios.git",
            .upToNextMinor(from: "1.0.4"),
        ),
        .package(id: "rollbar.rollbar-apple", from: "3.4.0"),
        .package(
            url: "https://github.com/siteline/SwiftUI-Introspect.git",
            .upToNextMajor(from: "26.0.1"),
        ),
        .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.9.0"),
        .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.5.0"),
        .package(url: "https://github.com/CombineCommunity/CombineExt.git", from: "1.9.0"),
        .package(url: "https://github.com/auth0/JWTDecode.swift", from: "4.0.0"),
        .package(
            url: "https://github.com/AppsFlyerSDK/AppsFlyerFramework-Strict.git",
            .upToNextMinor(from: "6.18.0"),
        ),
        .package(
            url: "https://github.com/pointfreeco/swift-snapshot-testing",
            .upToNextMajor(from: "1.19.2"),
        ),
//        .package(
//            url: "git@github.com:wallester/mobile-frontend-api-package.git",
//            .upToNextMajor(from: "0.1.339"),
//        ),
        .package(
            url: "https://github.com/firebase/firebase-ios-sdk.git",
            .upToNextMinor(from: "12.13.0"),
        ),
    ],
    targets: [],
    swiftLanguageModes: [.v5],
)
