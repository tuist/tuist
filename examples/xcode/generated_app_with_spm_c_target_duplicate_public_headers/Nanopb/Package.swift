// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Nanopb",
    products: [
        .library(name: "nanopb", targets: ["nanopb"]),
    ],
    targets: [
        .target(
            name: "nanopb",
            path: ".",
            sources: [
                "pb.h",
                "pb_common.h",
                "pb_common.c",
            ],
            publicHeadersPath: "spm_headers"
        ),
    ]
)
