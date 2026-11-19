// swift-tools-version:5.9
import PackageDescription

// Mirrors aws-crt-swift's AwsCCommon: public headers include sibling `.inl` files, and the package excludes its
// public header subtree from compilation.
let package = Package(
    name: "VendoredPkg",
    products: [.library(name: "CCommon", targets: ["CCommon"])],
    targets: [
        .target(
            name: "CCommon",
            path: "common",
            exclude: ["include/vc/common/"]
        ),
    ]
)
