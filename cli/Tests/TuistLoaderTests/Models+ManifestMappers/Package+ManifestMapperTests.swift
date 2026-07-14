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
    @Test func existingPackageDeclarationsRemainSourceAndSerializationCompatible() throws {
        let package = ProjectDescription.Package.package(path: "Package")
        let emptyProject = ProjectDescription.Project(name: "Empty", packages: [])
        let project = ProjectDescription.Project(
            name: "Project",
            packages: [package]
        )
        let encoded = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(ProjectDescription.Project.self, from: encoded)

        let decodedPackagePath = switch project.packages[0] {
        case let .local(path): path
        case .remote, .registry: Path("Unexpected")
        }

        #expect(decodedPackagePath == Path("Package"))
        #expect(emptyProject.packages.isEmpty)
        #expect(emptyProject.packageDependencies == nil)
        #expect(project.packageDependencies == nil)
        #expect(decoded == project)
    }

    @Test func projectWithPackageTraitsRoundTripsThroughCodable() throws {
        let project = ProjectDescription.Project(
            name: "Project",
            packages: [
                .package(path: "Package", traits: ["FeatureA"]),
                .package(url: "https://example.com/package.git", from: "1.0.0", traits: []),
                .package(id: "example.unconfigured", from: "1.0.0"),
            ]
        )

        let encoded = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(ProjectDescription.Project.self, from: encoded)

        #expect(project.packages.count == 3)
        #expect(project.packageDependencies?.count == 3)
        #expect(project.packageDependencies?[2].traits == [.defaults])
        #expect(decoded == project)
    }

    @Test func mapsProjectPackageTraitsToXcodeGraph() async throws {
        let generatorPaths = GeneratorPaths(manifestDirectory: "/Project", rootDirectory: "/Project")
        let project = ProjectDescription.Project(
            name: "Project",
            packages: [
                .package(path: "Package", traits: ["FeatureA"]),
                .package(url: "https://example.com/package.git", from: "1.0.0", traits: []),
                .package(id: "example.package", exact: "1.0.0"),
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
            .init(package: .local(path: "/Project/Package"), traits: ["FeatureA"]),
            .init(
                package: .remote(
                    url: "https://example.com/package.git",
                    requirement: .range(from: "1.0.0", to: "2.0.0")
                ),
                traits: []
            ),
        ])
    }

    @Test func packageDependencyUsesSwiftPackageManagerAlignedKindAndTypedTraits() {
        let dependency = ProjectDescription.Package.Dependency.package(
            url: "https://example.com/package.git",
            from: "1.0.0",
            traits: [.defaults, "FeatureA"]
        )

        #expect(
            dependency.kind == .sourceControl(
                location: "https://example.com/package.git",
                requirement: .range("1.0.0" ..< "2.0.0")
            )
        )
        #expect(dependency.traits == [.defaults, "FeatureA"])
    }

    @Test func packageDependencyUsesDistinctSourceControlAndRegistryRequirements() {
        let sourceControlDependency = ProjectDescription.Package.Dependency(
            kind: .sourceControl(
                location: "https://example.com/package.git",
                requirement: .branch("main")
            )
        )
        let registryDependency = ProjectDescription.Package.Dependency(
            kind: .registry(
                id: "example.package",
                requirement: .range("1.0.0" ..< "2.0.0")
            )
        )

        #expect(
            sourceControlDependency.package == .remote(
                url: "https://example.com/package.git",
                requirement: .branch("main")
            )
        )
        #expect(
            registryDependency.package == .registry(
                identifier: "example.package",
                requirement: .range(from: "1.0.0", to: "2.0.0")
            )
        )
    }
}
