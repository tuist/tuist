import Foundation
import Path
import ProjectDescription
import Testing
import XcodeGraph
@testable import TuistLoader

struct PackageManifestMapperTests {
    @Test func packageWithTraitsRoundTripsThroughCodable() throws {
        let packages: [ProjectDescription.Package] = [
            .package(path: "Package", traits: ["FeatureA"]),
            .package(url: "https://example.com/package.git", from: "1.0.0", traits: []),
            .package(id: "example.package", exact: "1.0.0", traits: nil),
        ]

        let encoded = try JSONEncoder().encode(packages)
        let decoded = try JSONDecoder().decode([ProjectDescription.Package].self, from: encoded)

        #expect(decoded == packages)
    }

    @Test func mapsTraitsToXcodeGraphPackages() throws {
        let generatorPaths = GeneratorPaths(manifestDirectory: "/Project", rootDirectory: "/Project")

        let local = try XcodeGraph.Package.from(
            manifest: .package(path: "Package", traits: ["FeatureA"]),
            generatorPaths: generatorPaths
        )
        let remote = try XcodeGraph.Package.from(
            manifest: .package(url: "https://example.com/package.git", from: "1.0.0", traits: []),
            generatorPaths: generatorPaths
        )
        let registry = try XcodeGraph.Package.from(
            manifest: .package(id: "example.package", exact: "1.0.0", traits: ["FeatureB"]),
            generatorPaths: generatorPaths
        )

        #expect(local == .local(path: "/Project/Package", traits: ["FeatureA"]))
        #expect(
            remote == .remote(
                url: "https://example.com/package.git",
                requirement: .upToNextMajor("1.0.0"),
                traits: []
            )
        )
        #expect(
            registry == .remote(
                url: "example.package",
                requirement: .exact("1.0.0"),
                traits: ["FeatureB"]
            )
        )
    }
}
