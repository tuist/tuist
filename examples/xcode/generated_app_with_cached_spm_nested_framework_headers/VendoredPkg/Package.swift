// swift-tools-version:5.9
import PackageDescription

// Mirrors the Adjust SDK's layout: the public headers are relative symlinks under
// `include/NestedKit/`, and the umbrella header imports them framework-style.
let package = Package(
    name: "VendoredPkg",
    products: [.library(name: "NestedKit", targets: ["NestedKit"])],
    targets: [
        .target(
            name: "NestedKit",
            path: "NestedKit",
            cSettings: [.headerSearchPath("")]
        ),
    ]
)
