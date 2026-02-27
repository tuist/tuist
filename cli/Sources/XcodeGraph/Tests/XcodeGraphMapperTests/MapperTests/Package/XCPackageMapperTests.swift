import Path
import Testing
import XcodeGraph
import XcodeProj
@testable import XcodeGraphMapper

@Suite
struct XCPackageMapperTests {
    let mapper: XCPackageMapper

    init() {
        mapper = XCPackageMapper()
    }

    @Test("Maps a remote package with a valid URL and up-to-next-major requirement")
    func mapPackageWithValidURL() throws {
        // Given
        let package = XCRemoteSwiftPackageReference(
            repositoryURL: "https://github.com/example/package.git",
            versionRequirement: .upToNextMajorVersion("1.0.0")
        )

        // When
        let result = try mapper.map(package: package)

        // Then
        #expect(
            result
                == .remote(
                    url: "https://github.com/example/package.git",
                    requirement: .upToNextMajor("1.0.0")
                )
        )
    }

    @Test("Maps an up-to-next-major version requirement correctly")
    func mapRequirementUpToNextMajor() throws {
        // Given
        let package = XCRemoteSwiftPackageReference(
            repositoryURL: "https://github.com/example/package.git",
            versionRequirement: .upToNextMajorVersion("1.0.0")
        )

        let mapped = try mapper.map(package: package)

        // Then
        #expect(mapped.requirement == .upToNextMajor("1.0.0"))
    }

    @Test("Maps an up-to-next-minor version requirement correctly")
    func mapRequirementUpToNextMinor() throws {
        // Given
        let package = XCRemoteSwiftPackageReference(
            repositoryURL: "https://github.com/example/package.git",
            versionRequirement: .upToNextMinorVersion("1.2.0")
        )

        // When
        let mapped = try mapper.map(package: package)

        // Then
        #expect(mapped.requirement == .upToNextMinor("1.2.0"))
    }

    @Test("Maps an exact version requirement correctly")
    func mapRequirementExact() throws {
        // Given
        let package = XCRemoteSwiftPackageReference(
            repositoryURL: "https://github.com/example/package.git",
            versionRequirement: .exact("1.2.3")
        )

        // When
        let mapped = try mapper.map(package: package)

        // Then
        #expect(mapped.requirement == .exact("1.2.3"))
    }

    @Test("Maps a range version requirement correctly")
    func mapRequirementRange() throws {
        // Given
        let package = XCRemoteSwiftPackageReference(
            repositoryURL: "https://github.com/example/package.git",
            versionRequirement: .range(from: "1.0.0", to: "2.0.0")
        )

        // When
        let mapped = try mapper.map(package: package)

        // Then
        #expect(mapped.requirement == .range(from: "1.0.0", to: "2.0.0"))
    }

    @Test("Maps a branch-based version requirement correctly")
    func mapRequirementBranch() throws {
        // Given
        let package = XCRemoteSwiftPackageReference(
            repositoryURL: "https://github.com/example/package.git",
            versionRequirement: .branch("main")
        )

        // When
        let mapped = try mapper.map(package: package)

        // Then
        #expect(mapped.requirement == .branch("main"))
    }

    @Test("Maps a revision-based version requirement correctly")
    func mapRequirementRevision() throws {
        // Given
        let package = XCRemoteSwiftPackageReference(
            repositoryURL: "https://github.com/example/package.git",
            versionRequirement: .revision("abc123")
        )

        // When
        let mapped = try mapper.map(package: package)

        // Then
        #expect(mapped.requirement == .revision("abc123"))
    }

    @Test("Maps a missing version requirement to up-to-next-major(0.0.0)")
    func mapRequirementNoVersionRequirement() throws {
        // Given
        let package = XCRemoteSwiftPackageReference(
            repositoryURL: "https://github.com/example/package.git",
            versionRequirement: nil
        )

        // When
        let mapped = try mapper.map(package: package)

        // Then
        #expect(mapped.requirement == .upToNextMajor("0.0.0"))
    }

    @Test("Maps a local package reference correctly")
    func mapLocalPackage() async throws {
        // Given
        let xcodeProj = try await XcodeProj.test()
        let localPackage = XCLocalSwiftPackageReference(relativePath: "Packages/Example")

        // When
        let result = try mapper.map(package: localPackage, sourceDirectory: xcodeProj.srcPath)

        // Then
        let expectedPath = xcodeProj.srcPath.appending(
            try RelativePath(validating: "Packages/Example")
        )
        #expect(result == .local(path: expectedPath))
    }

    @Test("Throws an error if remote package has no repository URL")
    func mapPackageWithoutURL() throws {
        // Given
        let package = XCRemoteSwiftPackageReference(
            repositoryURL: "",
            versionRequirement: .exact("1.2.3")
        )
        package.repositoryURL = nil

        // When / Then (expecting a throw)
        #expect {
            try mapper.map(package: package)
        } throws: { error in
            // Because 'repositoryURL' was set to nil,
            // we verify that the correct error message appears.
            return error.localizedDescription == "The repository URL is missing for the package: Unknown Package."
        }
    }
}

extension Package {
    fileprivate var requirement: Requirement? {
        switch self {
        case let .remote(_, requirement):
            return requirement
        case .local:
            return nil
        }
    }
}
