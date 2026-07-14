// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "CLibPkg",
    products: [.library(name: "CLib", targets: ["CLib"])],
    targets: [.target(name: "CLib")]
)
