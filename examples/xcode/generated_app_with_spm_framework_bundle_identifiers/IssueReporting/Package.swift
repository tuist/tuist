// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "IssueReporting",
    products: [.library(name: "IssueReporting", targets: ["_IssueReporting"])],
    targets: [
        .target(name: "IssueReporting"),
        .target(name: "_IssueReporting", dependencies: ["IssueReporting"]),
    ]
)
