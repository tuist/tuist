// swift-tools-version:5.9
import PackageDescription

// NestedKit mirrors the Adjust SDK's layout: the public headers are relative symlinks under
// `include/NestedKit/`, and the umbrella header imports them framework-style. QuotedKit mirrors
// SDWebImage's: its headers import each other with quotes, as in `#import "QKCompat.h"`.
let package = Package(
    name: "VendoredPkg",
    products: [
        .library(name: "NestedKit", targets: ["NestedKit"]),
        .library(name: "QuotedKit", targets: ["QuotedKit"]),
    ],
    targets: [
        .target(
            name: "NestedKit",
            path: "NestedKit",
            cSettings: [.headerSearchPath("")]
        ),
        .target(
            name: "QuotedKit",
            path: "QuotedKit",
            sources: ["Core"],
            cSettings: [.headerSearchPath("Core")]
        ),
    ]
)
