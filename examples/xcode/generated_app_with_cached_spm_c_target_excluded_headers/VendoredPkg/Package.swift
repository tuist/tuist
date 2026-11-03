// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "VendoredPkg",
    products: [.library(name: "CVendored", targets: ["CVendored"])],
    targets: [
        .target(
            name: "CVendored",
            path: "src",
            exclude: ["external"],
            publicHeadersPath: ".",
            cSettings: [.headerSearchPath("external")]
        ),
    ]
)
