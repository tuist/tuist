import Foundation
import Testing
@testable import SwifterPMCore

struct ModelsTests {
    @Test
    func resolvedPinHelpersValidateRequiredState() throws {
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

        #expect(try pin.revision() == "abcdef1234567890")
        #expect(try pin.versionString() == "1.2.3")
        #expect(PinKind.checkoutDirectoryName(pin) == "foo")
        #expect(PinKind.isSourceControl(pin.kind))
        #expect(!PinKind.isRegistry(pin.kind))

        #expect(throws: (any Error).self) {
            try ResolvedPin(
                identity: "bar",
                kind: "remoteSourceControl",
                location: "https://github.com/example/bar",
                state: ResolvedState(branch: nil, revision: nil, version: "1.0.0")
            ).revision()
        }
    }

    @Test
    func registryIdentityAndDownloadSubpathHelpers() throws {
        let (scope, name) = try PinKind.registryIdentityParts("example.package")
        #expect(scope == "example")
        #expect(name == "package")

        let pin = ResolvedPin(
            identity: "example.package",
            kind: "registry",
            location: "",
            state: ResolvedState(branch: nil, revision: nil, version: "1.2.3")
        )
        #expect(PinKind.isRegistry(pin.kind))
        #expect(try PinKind.registryDownloadSubpath(pin) == "example/package/1.2.3")
        #expect(throws: (any Error).self) {
            try PinKind.registryIdentityParts("unscoped")
        }
    }

    @Test
    func generatedPackagePathComponentsAreSanitized() throws {
        let sourcePin = ResolvedPin(
            identity: "bad/identity",
            kind: "remoteSourceControl",
            location: "file:///tmp/Foo%0ABar.git",
            state: ResolvedState(branch: nil, revision: "abcdef1234567890", version: nil)
        )
        let registryPin = ResolvedPin(
            identity: "example.bad/package",
            kind: "registry",
            location: "",
            state: ResolvedState(branch: nil, revision: nil, version: "1.2.3\nbeta")
        )

        #expect(PinKind.checkoutDirectoryName(sourcePin) == "Foo_0ABar")
        #expect(try PinKind.registryDownloadSubpath(registryPin) == "example/bad_package/1.2.3_beta")
    }

    @Test
    func readAndWriteResolvedFileRoundTripsInsidePackageDirectory() async throws {
        try await withTemporaryDirectory { root in
            try await writeMinimalPackageManifest(at: root, name: "Fixture")
            let resolved = try ResolvedPins(
                originHash: await ResolvedFile.packageOriginHash(packageDir: root),
                pins: [
                    ResolvedPin(
                        identity: "foo",
                        kind: "remoteSourceControl",
                        location: "https://github.com/example/foo",
                        state: ResolvedState(
                            branch: nil, revision: "abcdef123456", version: "1.0.0"
                        )
                    ),
                ],
                version: 3
            )

            try await ResolvedFile.write(packageDir: root, resolved: resolved)
            #expect(try await ResolvedFile.read(packageDir: root).pins == resolved.pins)
            #expect(try await ResolvedFile.read(packageDir: root).originHash == resolved.originHash)
            #expect(try await ResolvedFile.readIfCurrent(packageDir: root)?.pins == resolved.pins)

            let resolvedFilePath = root.appendingPathComponent("Package.resolved")
            let rawData = try await fileSystem.readFile(at: resolvedFilePath.absolutePath)
            let rawContents = try #require(String(data: rawData, encoding: .utf8))
            #expect(rawContents.contains("https://github.com/example/foo"))
            #expect(!rawContents.contains(#"https:\/\/github.com\/example\/foo"#))
        }
    }

    @Test
    func registryPinNormalizesOriginalLocationFromReplaceSCMWithRegistry() async throws {
        // SwiftPM emits `originalLocation` on pins it rewrote via
        // --replace-scm-with-registry so the next resolve can skip the
        // registry identifier lookup. Dropping it on the read/write
        // roundtrip means subsequent resolves needlessly hit the registry
        // again.
        try await withTemporaryDirectory { root in
            try await writeMinimalPackageManifest(at: root, name: "Fixture")
            let resolved = try ResolvedPins(
                originHash: await ResolvedFile.packageOriginHash(packageDir: root),
                pins: [
                    ResolvedPin(
                        identity: "apple.swift-log",
                        kind: "registry",
                        location: "",
                        state: ResolvedState(branch: nil, revision: nil, version: "1.5.0"),
                        originalLocation: "https://github.com/Apple/swift-log.git"
                    ),
                    ResolvedPin(
                        identity: "example.package",
                        kind: "registry",
                        location: "",
                        state: ResolvedState(branch: nil, revision: nil, version: "2.0.0"),
                        originalLocation: "HTTPS://Source.Example.com/Tuist/SwifterPM.git"
                    ),
                ],
                version: 3
            )

            try await ResolvedFile.write(packageDir: root, resolved: resolved)
            let readBack = try await ResolvedFile.read(packageDir: root)
            let readBackByIdentity = Dictionary(uniqueKeysWithValues: readBack.pins.map {
                ($0.identity, $0)
            })
            #expect(readBackByIdentity["apple.swift-log"]?.originalLocation == "https://github.com/apple/swift-log")
            #expect(readBackByIdentity["example.package"]?.originalLocation == "https://source.example.com/Tuist/SwifterPM.git")

            let resolvedFilePath = root.appendingPathComponent("Package.resolved")
            let rawData = try await fileSystem.readFile(at: resolvedFilePath.absolutePath)
            let rawPayload = try #require(
                JSONSerialization.jsonObject(with: rawData) as? [String: Any]
            )
            let rawPins = try #require(rawPayload["pins"] as? [[String: Any]])
            let rawPinsByIdentity = Dictionary(
                uniqueKeysWithValues: rawPins.compactMap { pin -> (String, [String: Any])? in
                    guard let identity = pin["identity"] as? String else { return nil }
                    return (identity, pin)
                }
            )
            #expect(rawPinsByIdentity["apple.swift-log"]?["originalLocation"] as? String == "https://github.com/apple/swift-log")
            #expect(rawPinsByIdentity["example.package"]?["originalLocation"] as? String ==
                "https://source.example.com/Tuist/SwifterPM.git")
        }
    }

    @Test
    func writeNormalizesRemoteLocationsAndSkipsIdenticalRewrites() async throws {
        try await withTemporaryDirectory { root in
            try await writeMinimalPackageManifest(at: root, name: "Fixture")
            let pins = [
                ResolvedPin(
                    identity: "CombineExt",
                    kind: "remoteSourceControl",
                    location: "https://github.com/CombineCommunity/CombineExt.git",
                    state: ResolvedState(
                        branch: nil, revision: "abcdef123456", version: "1.0.0"
                    )
                ),
                ResolvedPin(
                    identity: "dd-sdk-ios",
                    kind: "remoteSourceControl",
                    location: "git@github.com:DataDog/dd-sdk-ios.git",
                    state: ResolvedState(
                        branch: nil, revision: "abcdef123456", version: "1.0.0"
                    )
                ),
                ResolvedPin(
                    identity: "swifterpm",
                    kind: "remoteSourceControl",
                    location: "https://gitlab.com/Tuist/SwifterPM.git",
                    state: ResolvedState(
                        branch: nil, revision: "abcdef123456", version: "1.0.0"
                    )
                ),
                ResolvedPin(
                    identity: "generic",
                    kind: "remoteSourceControl",
                    location: "HTTPS://Source.Example.com/Tuist/SwifterPM.git",
                    state: ResolvedState(
                        branch: nil, revision: "abcdef123456", version: "1.0.0"
                    )
                ),
                ResolvedPin(
                    identity: "LocalPackage",
                    kind: "localSourceControl",
                    location: "file:///tmp/LocalPackage.git",
                    state: ResolvedState(
                        branch: nil, revision: "abcdef123456", version: "1.0.0"
                    )
                ),
            ]
            let resolved = try ResolvedPins(
                originHash: await ResolvedFile.packageOriginHash(packageDir: root),
                pins: pins,
                version: 3
            )

            try await ResolvedFile.write(packageDir: root, resolved: resolved)
            let resolvedFilePath = try root.appendingPathComponent("Package.resolved").absolutePath
            let rawData = try await fileSystem.readFile(at: resolvedFilePath)
            let rawPayload = try #require(
                JSONSerialization.jsonObject(with: rawData) as? [String: Any]
            )
            let rawPins = try #require(rawPayload["pins"] as? [[String: Any]])
            let rawPinsByIdentity = Dictionary(
                uniqueKeysWithValues: rawPins.compactMap { pin -> (String, [String: Any])? in
                    guard let identity = pin["identity"] as? String else { return nil }
                    return (identity, pin)
                }
            )
            let rawLocations = Set(rawPins.compactMap { $0["location"] as? String })
            #expect(
                try await ResolvedFile.read(packageDir: root).pins
                    == resolved.normalizedForResolvedFile().pins)
            #expect(Set(rawPinsByIdentity.keys) == Set([
                "LocalPackage",
                "combineext",
                "dd-sdk-ios",
                "generic",
                "swifterpm",
            ]))
            #expect(rawPinsByIdentity["combineext"]?["location"] as? String == "https://github.com/combinecommunity/combineext")
            #expect(rawPinsByIdentity["dd-sdk-ios"]?["location"] as? String == "git@github.com:datadog/dd-sdk-ios")
            #expect(rawPinsByIdentity["swifterpm"]?["location"] as? String == "https://gitlab.com/tuist/swifterpm")
            #expect(rawPinsByIdentity["generic"]?["location"] as? String == "https://source.example.com/Tuist/SwifterPM.git")
            #expect(rawPinsByIdentity["LocalPackage"]?["location"] as? String == "file:///tmp/LocalPackage.git")
            #expect(!rawLocations.contains("https://github.com/CombineCommunity/CombineExt.git"))
            #expect(!rawLocations.contains("git@github.com:DataDog/dd-sdk-ios.git"))
            #expect(!rawLocations.contains("HTTPS://Source.Example.com/Tuist/SwifterPM.git"))

            // Rewriting unchanged content must leave the file untouched.
            let modificationDate = try await fileSystem.fileMetadata(at: resolvedFilePath)?
                .lastModificationDate
            try await ResolvedFile.write(packageDir: root, resolved: resolved)
            #expect(
                try await fileSystem.fileMetadata(at: resolvedFilePath)?.lastModificationDate
                    == modificationDate)
            #expect(try await fileSystem.readFile(at: resolvedFilePath) == rawData)
        }
    }

    @Test
    func legacyResolvedFileDecodesAndWritesCurrentSchema() async throws {
        try await withTemporaryDirectory { root in
            try await writeMinimalPackageManifest(at: root, name: "Fixture")
            try await fileSystem.atomicWrite(
                """
                {
                  "object": {
                    "pins": [
                      {
                        "package": "DeckOfPlayingCards",
                        "repositoryURL": "/tmp/deck-of-playing-cards",
                        "state": {
                          "revision": "abcdef123456",
                          "version": "1.0.0"
                        }
                      }
                    ]
                  },
                  "version": 1
                }
                """,
                to: root.appendingPathComponent("Package.resolved")
            )

            let resolved = try await ResolvedFile.read(packageDir: root)
            let pin = try #require(resolved.pins.first)
            #expect(resolved.version == 3)
            #expect(pin.identity == "deck-of-playing-cards")
            #expect(pin.kind == "localSourceControl")
            #expect(pin.location == "/tmp/deck-of-playing-cards")

            try await ResolvedFile.write(packageDir: root, resolved: resolved)
            let rawData = try await fileSystem.readFile(
                at: root.appendingPathComponent("Package.resolved").absolutePath
            )
            let rawContents = try #require(String(data: rawData, encoding: .utf8))
            #expect(rawContents.contains(#""pins" : ["#))
            #expect(rawContents.contains(#""version" : 3"#))
            #expect(!rawContents.contains(#""object""#))
        }
    }

    @Test
    func readIfCurrentReturnsNilWhenOriginHashDoesNotMatch() async throws {
        try await withTemporaryDirectory { root in
            try await writeMinimalPackageManifest(at: root, name: "Fixture")
            try await ResolvedFile.write(
                packageDir: root,
                resolved: ResolvedPins(originHash: "stale", pins: [], version: 3)
            )

            #expect(try await ResolvedFile.readIfCurrent(packageDir: root) == nil)
        }
    }

    @Test
    func downloadedMixedRegistryAndGitHubResolvedFixtureDecodes() async throws {
        let fixture = try await fixtureURL("MixedRegistryAndGitHub")
        let resolved = try await ResolvedFile.read(packageDir: fixture)
        let packageManifest = try String(
            data: await fileSystem.readFile(at: fixture.appendingPathComponent("Package.swift").absolutePath),
            encoding: .utf8
        )
        let identities = Set(resolved.pins.map(\.identity))

        #expect(resolved.version == 3)
        #expect(
            resolved.originHash
                == "4d417b634d3a503175acfb1710b87fdc09ada364bff47b2a716050126ff3a1e0")
        #expect(packageManifest?.contains(".package(id: \"marmelroy.PhoneNumberKit\"") == true)
        #expect(
            packageManifest?.contains("https://github.com/firebase/firebase-ios-sdk.git") == true)
        #expect(resolved.pins.count == 27)
        #expect(identities.contains("firebase-ios-sdk"))
        #expect(identities.contains("marmelroy.PhoneNumberKit"))
        #expect(resolved.pins.filter { PinKind.isRegistry($0.kind) }.count == 3)
        #expect(resolved.pins.filter { PinKind.isSourceControl($0.kind) }.count == 24)
    }
}
