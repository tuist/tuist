import ProjectDescription

let project = Project(
    name: "App",
    targets: [
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.App",
            sources: ["App/Sources/**"],
            dependencies: [
                .xcframework(path: "App/XCFrameworks/MyStaticLibrary.xcframework"),
                .xcframework(
                    path: "App/XCFrameworks/MyFramework.xcframework",
                    expectedSignature: nil
                ),
                .xcframework(
                    path: "App/XCFrameworks/SignedXCFramework.xcframework",
                    expectedSignature: .signedWithAppleCertificate(
                        teamIdentifier: "U6LC622NKF",
                        teamName: "Tuist GmbH"
                    )
                ),
                .xcframework(
                    path: "App/XCFrameworks/SelfSignedXCFramework.xcframework",
                    expectedSignature: .selfSigned(
                        fingerprint: "EF61C3C0339FC84805357AFEC2E0BB0E6A0D5EE64165B333F934BF9E282785BC"
                    )
                ),
            ]
        ),
        .target(
            name: "AppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.AppTests",
            infoPlist: .default,
            sources: ["App/Tests/**"],
            resources: [],
            dependencies: [.target(name: "App")]
        ),
    ]
)
