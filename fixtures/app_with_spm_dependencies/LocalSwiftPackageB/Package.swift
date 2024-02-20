// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LocalSwiftPackageB",
    defaultLocalization: "en",
    products: [.library(name: "LibraryA", targets: ["LibraryA"])],
    targets: [
        .target(name: "LibraryA", dependencies: ["LibraryAProxy"]),
        .target(
            name: "LibraryAProxy"
        ),
    ],
    cxxLanguageStandard: .cxx17
)
