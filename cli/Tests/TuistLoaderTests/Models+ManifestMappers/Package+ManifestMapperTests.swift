import FileSystem
import Foundation
import Path
import ProjectDescription
import Testing
import TuistCore
import TuistSupport
import XcodeGraph
@testable import TuistLoader

struct PackageManifestMapperTests {
    @Test func projectWithPackageTraitsRoundTripsThroughCodable() throws {
        let localPackage = ProjectDescription.Package.package(path: "Package")
        let remotePackage = ProjectDescription.Package.package(url: "https://example.com/package.git", from: "1.0.0")
        let project = ProjectDescription.Project(
            name: "Project",
            packages: [localPackage, remotePackage],
            packageTraits: [
                localPackage: ["FeatureA"],
                remotePackage: [],
            ]
        )

        let encoded = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(ProjectDescription.Project.self, from: encoded)

        #expect(decoded == project)
    }

    @Test func mapsProjectPackageTraitsToXcodeGraph() async throws {
        let generatorPaths = GeneratorPaths(manifestDirectory: "/Project", rootDirectory: "/Project")
        let localPackage = ProjectDescription.Package.package(path: "Package")
        let remotePackage = ProjectDescription.Package.package(url: "https://example.com/package.git", from: "1.0.0")
        let registryPackage = ProjectDescription.Package.package(id: "example.package", exact: "1.0.0")
        let project = ProjectDescription.Project(
            name: "Project",
            packages: [localPackage, remotePackage, registryPackage],
            packageTraits: [
                localPackage: ["FeatureA"],
                remotePackage: [],
                registryPackage: ["FeatureB"],
            ]
        )
        let mappedProject = try await XcodeGraph.Project.from(
            manifest: project,
            generatorPaths: generatorPaths,
            plugins: .none,
            externalDependencies: [:],
            resourceSynthesizerPathLocator: MockResourceSynthesizerPathLocator(),
            type: .local,
            fileSystem: FileSystem(),
            contentHasher: MockContentHashing()
        )

        #expect(mappedProject.packageTraits == [
            .local(path: "/Project/Package"): ["FeatureA"],
            .remote(url: "https://example.com/package.git", requirement: .upToNextMajor("1.0.0")): [],
            .remote(url: "example.package", requirement: .exact("1.0.0")): ["FeatureB"],
        ])
    }
}
