// swift-tools-version: 5.9
@preconcurrency import PackageDescription

#if TUIST
import ProjectDescription

let packageSettings = PackageSettings(
    productTypes: [
        "SVProgressHUD": .staticFramework
    ]
)
#endif

let package = Package(
    name: "PackageName",
    dependencies: [
        .package(url: "https://github.com/SVProgressHUD/SVProgressHUD.git", exact: "2.3.1"),
    ]
)
