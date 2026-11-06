// swift-tools-version: 5.9
import PackageDescription

// Stands in for the local `../AdaSDK` package that ExternalDependenciesLarger
// depends on by path. It contributes no pins to the fixture's lockfile.
let package = Package(name: "AdaSDK")
