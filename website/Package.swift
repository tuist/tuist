// swift-tools-version:5.2.0
import PackageDescription

// This is necessary for 2 reasons:
// 1. It tricks SPM to not include the website/ directory in the generated Xcode project.
//    Because there's a node_modules in it, Xcode is very slow indexing things.
//    https://forums.swift.org/t/hiding-ignoring-directories-from-xcode-when-opening-swift-packages/35431/6
// 2. Netlify detects that there's a Package.swift and tries to build the package. There's
//    no way to configure that on Netlify and therefore we need an empty target here.
let package = Package(
    name: "website",
    platforms: [.macOS(.v10_12)],
    products: [],
    dependencies: [],
    targets: [
        .target(name: "website"),
    ]
)
