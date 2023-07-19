import ProjectDescription

let dependencies = Dependencies(
    swiftPackageManager: [
        .package(url: "https://github.com/google/GoogleSignIn-iOS", .upToNextMinor(from: "7.0.0"))
    ],
    platforms: [.iOS]
)
