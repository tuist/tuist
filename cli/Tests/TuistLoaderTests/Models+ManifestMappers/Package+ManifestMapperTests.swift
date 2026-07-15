import FileSystem
import Foundation
import Path
@_spi(TuistLoader) import ProjectDescription
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
        let encodedObject = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        let decodedPackagePath = switch project.packages[0] {
        case let .local(path): path
        case .remote, .registry: Path("Unexpected")
        }

        #expect(decodedPackagePath == Path("Package"))
        #expect(emptyProject.packages.isEmpty)
        #expect(emptyProject.packageDependencies.isEmpty)
        #expect(project.packageDependencies.count == 1)
        #expect(encodedObject["packageDependencies"] != nil)
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
        #expect(project.packageDependencies.count == 3)
        #expect(project.packageDependencies[2].traits == [.defaults])
        #expect(decoded == project)
    }

    @Test func projectDecodesLegacyPackageOnlyPayloadIntoCanonicalDependencies() throws {
        let project = ProjectDescription.Project(
            name: "Project",
            packages: [ProjectDescription.Package.package(path: "Package")]
        )
        let encoded = try JSONEncoder().encode(project)
        var encodedObject = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        encodedObject.removeValue(forKey: "packageDependencies")

        let decoded = try JSONDecoder().decode(
            ProjectDescription.Project.self,
            from: JSONSerialization.data(withJSONObject: encodedObject)
        )

        #expect(decoded.packages == project.packages)
        #expect(decoded.packageDependencies.count == 1)
        #expect(decoded.packageDependencies[0].traits == [.defaults])
    }

    @Test func legacyPackagesConvertToCanonicalDependenciesWithDefaultTraits() {
        let project = ProjectDescription.Project(
            name: "Project",
            packages: [
                ProjectDescription.Package.package(url: "https://example.com/package.git", from: "1.2.3"),
                ProjectDescription.Package.package(id: "example.package", exact: "2.0.0"),
            ]
        )

        #expect(project.packageDependencies == [
            .init(
                kind: .sourceControl(
                    location: "https://example.com/package.git",
                    requirement: .range("1.2.3" ..< "2.0.0")
                )
            ),
            .init(kind: .registry(id: "example.package", requirement: .exact("2.0.0"))),
        ])
    }

    @Test func projectRejectsConflictingEncodedPackageRepresentations() throws {
        let project = ProjectDescription.Project(
            name: "Project",
            packages: [.package(path: "Package", traits: ["FeatureA"])]
        )
        let encoded = try JSONEncoder().encode(project)
        var encodedObject = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        encodedObject["packages"] = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode([ProjectDescription.Package.package(path: "OtherPackage")])
        )
        let conflictingData = try JSONSerialization.data(withJSONObject: encodedObject)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ProjectDescription.Project.self, from: conflictingData)
        }
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

        #expect(mappedProject.packages == [
            .local(path: "/Project/Package", traits: ["FeatureA"]),
            .remote(
                url: "https://example.com/package.git",
                requirement: .range(from: "1.0.0", to: "2.0.0"),
                traits: []
            ),
            .remote(url: "example.package", requirement: .exact("1.0.0")),
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
