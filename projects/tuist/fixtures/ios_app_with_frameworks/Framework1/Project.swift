import ProjectDescription

let infoPlist: [String: InfoPlist.Value] = [
    "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
    "CFBundleExecutable": "$(EXECUTABLE_NAME)",
    "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
    "CFBundleInfoDictionaryVersion": "6.0",
    "CFBundleName": "$(PRODUCT_NAME)",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": "1.0",
    "CFBundleVersion": "1",
    "LSRequiresIPhoneOS": true,
    "NSHumanReadableCopyright": "Copyright ©. All rights reserved.",
    "Test": "Value",
]

let project = Project(
    name: "Framework1",
    targets: [
        Target(
            name: "Framework1",
            platform: .iOS,
            product: .framework,
            productName: "Framework1",
            bundleId: "io.tuist.Framework1",
            infoPlist: .dictionary(infoPlist),
            sources: "Sources/**",
            dependencies: [
                .project(target: "Framework2-iOS", path: "../Framework2"),
            ]
        ),
        Target(
            name: "Framework1Tests",
            platform: .iOS,
            product: .unitTests,
            productName: "Framework1Tests",
            bundleId: "io.tuist.Framework1Tests",
            infoPlist: "Config/Framework1Tests-Info.plist",
            sources: "Tests/**",
            dependencies: [
                .target(name: "Framework1"),
            ]
        ),
    ]
)
