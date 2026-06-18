import Foundation
import Testing
@testable import SwifterPMCore

struct CacheTests {
    @Test
    func cachePathsStayUnderProvidedRoot() async throws {
        try await withTemporaryDirectory { root in
            let cache = try await Cache(root: root)
            let pin = ResolvedPin(
                identity: "foo",
                kind: "remoteSourceControl",
                location: "https://github.com/example/foo.git",
                state: ResolvedState(
                    branch: nil,
                    revision: "abcdef1234567890",
                    version: "1.2.3"
                )
            )

            #expect(try cache.sourcePath(pin: pin).path.hasPrefix(root.path))
            #expect(
                try cache.archivePath(url: pin.location, revision: pin.revision()).path.hasPrefix(
                    root.path)
            )
            #expect(cache.remoteVersionsPath(location: pin.location).path.hasPrefix(root.path))
            #expect(
                cache.registryArchivePath(
                    identity: "example.package",
                    version: "1.2.3",
                    registryURL: "https://registry.example.com",
                    checksum: "abcdef1234567890"
                ).path
                    .hasPrefix(
                        root.path))
        }
    }

    @Test
    func initializesExpectedCacheDirectories() async throws {
        try await withTemporaryDirectory { root in
            _ = try await Cache(root: root)

            for path in [
                "sources",
                "archives",
                "registry/archives",
                "metadata/remotes",
                "locks",
                "virtual/checkouts",
                "artifacts",
            ] {
                #expect(try await fileSystem.exists(root.appendingPathComponent(path).absolutePath))
            }
        }
    }

    @Test
    func sourcePathRejectsRegistryPins() async throws {
        try await withTemporaryDirectory { root in
            let cache = try await Cache(root: root)
            let pin = ResolvedPin(
                identity: "example.package",
                kind: "registry",
                location: "",
                state: ResolvedState(branch: nil, revision: nil, version: nil)
            )

            #expect(throws: (any Error).self) {
                try cache.sourcePath(pin: pin)
            }
        }
    }

    @Test
    func registryCachePathsIncludeRegistryURLAndChecksum() async throws {
        try await withTemporaryDirectory { root in
            let cache = try await Cache(root: root)

            let source = cache.registrySourcePath(
                identity: "example.package",
                version: "1.2.3",
                registryURL: "https://registry.example.com",
                checksum: "abcdef1234567890"
            )
            let otherRegistrySource = cache.registrySourcePath(
                identity: "example.package",
                version: "1.2.3",
                registryURL: "https://other.example.com",
                checksum: "abcdef1234567890"
            )
            let otherChecksumSource = cache.registrySourcePath(
                identity: "example.package",
                version: "1.2.3",
                registryURL: "https://registry.example.com",
                checksum: "1234567890abcdef"
            )

            #expect(source != otherRegistrySource)
            #expect(source != otherChecksumSource)
            #expect(
                cache.registryArchivePath(
                    identity: "example.package",
                    version: "1.2.3",
                    registryURL: "https://registry.example.com",
                    checksum: "abcdef1234567890"
                )
                    != cache.registryArchivePath(
                        identity: "example.package",
                        version: "1.2.3",
                        registryURL: "https://other.example.com",
                        checksum: "abcdef1234567890"
                    ))
        }
    }

    @Test
    func generatedCachePathsSanitizeMetadataComponents() async throws {
        try await withTemporaryDirectory { root in
            let cache = try await Cache(root: root)
            let pin = ResolvedPin(
                identity: "bad/identity",
                kind: "remoteSourceControl",
                location: "https://github.com/example/foo.git",
                state: ResolvedState(
                    branch: "feature/path\nwith-control",
                    revision: "abcdef1234567890",
                    version: nil
                )
            )

            let sourcePath = try cache.sourcePath(pin: pin).path
            let registrySourcePath = cache.registrySourcePath(
                identity: "example.bad/package",
                version: "1.2.3\nbeta",
                registryURL: "https://registry.example.com",
                checksum: "abcdef1234567890"
            ).path
            let registryArchivePath = cache.registryArchivePath(
                identity: "example.bad/package",
                version: "1.2.3\nbeta",
                registryURL: "https://registry.example.com",
                checksum: "abcdef1234567890"
            ).path
            let artifactPath = cache.binaryArtifactDirectory(
                identity: "bad/identity",
                targetName: "Foo\nBar",
                checksum: "abcdef1234567890"
            ).path

            #expect(sourcePath.contains("bad_identity/feature_path_with-control-abcdef12"))
            #expect(registrySourcePath.contains("example.bad_package/1.2.3_beta-"))
            #expect(registryArchivePath.contains("-1.2.3_beta-"))
            #expect(registryArchivePath.hasSuffix("-abcdef1234567890.zip"))
            #expect(artifactPath.contains("bad_identity/Foo_Bar-abcdef123456"))
            for path in [sourcePath, registrySourcePath, registryArchivePath, artifactPath] {
                #expect(!path.contains("\n"))
                #expect(!path.contains("//"))
            }
        }
    }
}
