import Foundation
import Testing
@testable import SwifterPMCore

struct RestoreTests {
    @Test
    func restorePackageWithNoPinsUsesScopedScratchAndCache() async throws {
        try await withTemporaryDirectory { root in
            let scratch = root.appendingPathComponent("scratch")
            let cache = try await Cache(root: root.appendingPathComponent("cache"))

            try await WorkspaceRestorer.restorePackage(
                scratchDir: scratch,
                cache: cache,
                registryConfig: RegistryConfig(),
                resolved: ResolvedPins(originHash: nil, pins: [], version: 3),
                progress: nil
            )

            #expect(try await fileSystem.exists(scratch.appendingPathComponent("checkouts").absolutePath))
            #expect(
                try await fileSystem.exists(scratch.appendingPathComponent("registry/downloads").absolutePath))
        }
    }

    @Test
    func writeWorkspaceStateWritesSourceControlAndRegistryDependencies() async throws {
        try await withTemporaryDirectory { root in
            let package = root.appendingPathComponent("Package")
            let scratch = root.appendingPathComponent("scratch")
            try await writeCachedManifest(emptyManifest(), packageDir: package)

            let resolved = ResolvedPins(
                originHash: "origin",
                pins: [
                    ResolvedPin(
                        identity: "foo",
                        kind: "remoteSourceControl",
                        location: "https://github.com/example/foo.git",
                        state: ResolvedState(
                            branch: nil, revision: "abcdef1234567890", version: "1.2.3"
                        )
                    ),
                    ResolvedPin(
                        identity: "example.package",
                        kind: "registry",
                        location: "",
                        state: ResolvedState(branch: nil, revision: nil, version: "2.3.4")
                    ),
                ],
                version: 3
            )

            try await WorkspaceRestorer.writeWorkspaceState(
                packageDir: package, scratchDir: scratch, resolved: resolved, disableSandbox: false
            )

            let statePath = scratch.appendingPathComponent("workspace-state.json")
            let state = try #require(
                try JSONSerialization.jsonObject(
                    with: await fileSystem.readFile(at: statePath.absolutePath))
                    as? [String: Any])
            let object = try #require(state["object"] as? [String: Any])
            let dependencies = try #require(object["dependencies"] as? [[String: Any]])
            #expect(dependencies.count == 2)
            #expect(
                Set(
                    dependencies.compactMap {
                        ($0["packageRef"] as? [String: Any])?["identity"] as? String
                    })
                    == ["foo", "example.package"])
        }
    }

    @Test
    func writeWorkspaceStatePreservesAndSanitizesExistingPrebuilts() async throws {
        try await withTemporaryDirectory { root in
            let package = root.appendingPathComponent("Package")
            let scratch = root.appendingPathComponent("scratch")
            let statePath = scratch.appendingPathComponent("workspace-state.json")
            try await writeCachedManifest(emptyManifest(), packageDir: package)
            try await fileSystem.makeDirectory(at: scratch.absolutePath, options: [.createTargetParentDirectories])
            try await fileSystem.atomicWrite(
                JSONFormatter.prettyData([
                    "object": [
                        "artifacts": [],
                        "dependencies": [],
                        "prebuilts": [
                            [
                                "identity": "swift-syntax",
                                "version": "601.0.0",
                                "libraryName": "SwiftSyntax",
                                "path": "\(scratch.path)/prebuilts/swift-syntax\u{0}",
                                "checkoutPath": "\(scratch.path)/checkouts/swift-syntax\u{0}",
                                "products": ["SwiftSyntax"],
                                "includePath": ["Sources/_SwiftSyntaxCShims/include\u{0}"],
                                "cModules": ["_SwiftSyntaxCShims"],
                            ],
                        ],
                    ],
                    "version": 7,
                ]),
                to: statePath
            )

            try await WorkspaceRestorer.writeWorkspaceState(
                packageDir: package,
                scratchDir: scratch,
                resolved: ResolvedPins(originHash: "origin", pins: [], version: 3),
                disableSandbox: false
            )

            let state = try #require(
                try JSONSerialization.jsonObject(
                    with: await fileSystem.readFile(at: statePath.absolutePath))
                    as? [String: Any])
            let object = try #require(state["object"] as? [String: Any])
            let prebuilts = try #require(object["prebuilts"] as? [[String: Any]])
            let prebuilt = try #require(prebuilts.first)

            #expect(prebuilts.count == 1)
            #expect(prebuilt["identity"] as? String == "swift-syntax")
            #expect(prebuilt["libraryName"] as? String == "SwiftSyntax")
            #expect(prebuilt["path"] as? String == "\(scratch.path)/prebuilts/swift-syntax")
            #expect(prebuilt["checkoutPath"] as? String == "\(scratch.path)/checkouts/swift-syntax")
            #expect(
                prebuilt["includePath"] as? [String] == [
                    "Sources/_SwiftSyntaxCShims/include",
                ])
        }
    }

    @Test
    func writeWorkspaceStateUsesSourceControlManifestNameAndCheckoutSubpath() async throws {
        try await withTemporaryDirectory { root in
            let package = root.appendingPathComponent("Package")
            let scratch = root.appendingPathComponent("scratch")
            let checkout = scratch.appendingPathComponent("checkouts/deck-of-playing-cards")
            try await writeCachedManifest(emptyManifest(), packageDir: package)
            try await writeCachedManifest(
                emptyManifest(name: "DeckOfPlayingCards"),
                packageDir: checkout
            )

            let resolved = ResolvedPins(
                originHash: "origin",
                pins: [
                    ResolvedPin(
                        identity: "deck-of-playing-cards",
                        kind: "localSourceControl",
                        location: root.appendingPathComponent("deck-of-playing-cards").path,
                        state: ResolvedState(
                            branch: nil,
                            revision: "abcdef1234567890",
                            version: "1.0.0"
                        )
                    ),
                ],
                version: 3
            )

            try await WorkspaceRestorer.writeWorkspaceState(
                packageDir: package,
                scratchDir: scratch,
                resolved: resolved,
                disableSandbox: false
            )

            let statePath = scratch.appendingPathComponent("workspace-state.json")
            let state = try #require(
                try JSONSerialization.jsonObject(
                    with: await fileSystem.readFile(at: statePath.absolutePath))
                    as? [String: Any])
            let object = try #require(state["object"] as? [String: Any])
            let dependencies = try #require(object["dependencies"] as? [[String: Any]])
            let dependency = try #require(dependencies.first)
            let packageRef = try #require(dependency["packageRef"] as? [String: Any])

            #expect(packageRef["name"] as? String == "DeckOfPlayingCards")
            #expect(dependency["subpath"] as? String == "deck-of-playing-cards")
        }
    }

    @Test
    func writeWorkspaceStateIncludesTransitiveFileSystemDependencies() async throws {
        try await withTemporaryDirectory { root in
            let package = root.appendingPathComponent("Package")
            let localOne = package.appendingPathComponent("LocalOne")
            let localTwo = package.appendingPathComponent("LocalTwo")
            let scratch = root.appendingPathComponent("scratch")
            var rootManifest = emptyManifest()
            rootManifest["dependencies"] = [
                [
                    "fileSystem": [
                        [
                            "identity": "local-one",
                            "path": "LocalOne",
                        ],
                    ]
                ],
            ]
            var localOneManifest = emptyManifest(name: "LocalOne")
            localOneManifest["dependencies"] = [
                [
                    "fileSystem": [
                        [
                            "identity": "local-two",
                            "path": "../LocalTwo",
                        ],
                    ]
                ],
            ]

            try await writeCachedManifest(rootManifest, packageDir: package)
            try await writeCachedManifest(localOneManifest, packageDir: localOne)
            try await writeCachedManifest(emptyManifest(name: "LocalTwo"), packageDir: localTwo)

            try await WorkspaceRestorer.writeWorkspaceState(
                packageDir: package,
                scratchDir: scratch,
                resolved: ResolvedPins(originHash: "origin", pins: [], version: 3),
                disableSandbox: false
            )

            let statePath = scratch.appendingPathComponent("workspace-state.json")
            let state = try #require(
                try JSONSerialization.jsonObject(
                    with: await fileSystem.readFile(at: statePath.absolutePath))
                    as? [String: Any])
            let object = try #require(state["object"] as? [String: Any])
            let dependencies = try #require(object["dependencies"] as? [[String: Any]])
            let refs = dependencies.compactMap { $0["packageRef"] as? [String: Any] }
            let refsByIdentity = Dictionary(
                uniqueKeysWithValues: refs.compactMap { ref -> (String, [String: Any])? in
                    guard let identity = ref["identity"] as? String else { return nil }
                    return (identity, ref)
                }
            )

            #expect(Set(refsByIdentity.keys) == ["local-one", "local-two"])
            let expectedLocalOne = PathCanonicalizer.realpath(localOne).path
            let expectedLocalTwo = PathCanonicalizer.realpath(localTwo).path
            #expect(refsByIdentity["local-one"]?["location"] as? String == expectedLocalOne)
            #expect(refsByIdentity["local-two"]?["location"] as? String == expectedLocalTwo)
            #expect(
                Set(dependencies.compactMap { ($0["state"] as? [String: Any])?["path"] as? String })
                    == [expectedLocalOne, expectedLocalTwo])
        }
    }

    @Test
    func writeWorkspaceStateWritesRootLocalBinaryArtifacts() async throws {
        try await withTemporaryDirectory { root in
            let package = root.appendingPathComponent("Package")
            let scratch = root.appendingPathComponent("scratch")
            let framework = package.appendingPathComponent("XCFrameworks/Foo.xcframework")
            try await fileSystem.makeDirectory(at: framework.absolutePath, options: [.createTargetParentDirectories])
            try await fileSystem.atomicWrite(
                validXCFrameworkInfoPlist(),
                to: framework.appendingPathComponent("Info.plist")
            )
            try await writeCachedManifest(
                localBinaryTargetManifest(name: "Foo", path: "XCFrameworks/Foo.xcframework"),
                packageDir: package
            )

            let resolved = ResolvedPins(originHash: "origin", pins: [], version: 3)

            try await WorkspaceRestorer.writeWorkspaceState(
                packageDir: package, scratchDir: scratch, resolved: resolved, disableSandbox: false
            )

            let statePath = scratch.appendingPathComponent("workspace-state.json")
            let state = try #require(
                try JSONSerialization.jsonObject(
                    with: await fileSystem.readFile(at: statePath.absolutePath))
                    as? [String: Any])
            let object = try #require(state["object"] as? [String: Any])
            let artifacts = try #require(object["artifacts"] as? [[String: Any]])
            let artifact = try #require(artifacts.first)
            let packageRef = try #require(artifact["packageRef"] as? [String: Any])
            let source = try #require(artifact["source"] as? [String: Any])
            #expect(artifacts.count == 1)
            #expect(artifact["targetName"] as? String == "Foo")
            #expect(artifact["path"] as? String == PathCanonicalizer.realpath(framework).path)
            #expect(packageRef["kind"] as? String == "root")
            #expect(packageRef["identity"] as? String == "package")
            #expect(source["type"] as? String == "local")
        }
    }

    @Test
    func restorePackageDownloadsAndAdvertisesRemoteBinaryArtifacts() async throws {
        try await withTemporaryDirectory { root in
            let package = root.appendingPathComponent("Package")
            let scratch = root.appendingPathComponent("scratch")
            let cache = try await Cache(root: root.appendingPathComponent("cache"))
            let pin = ResolvedPin(
                identity: "binary",
                kind: "remoteSourceControl",
                location: "https://github.com/example/binary.git",
                state: ResolvedState(
                    branch: nil,
                    revision: "abcdef1234567890",
                    version: "1.0.0"
                )
            )
            let artifactURL = "https://example.com/Foo.zip"

            let zipPath = try await makeXCFrameworkZip(root: root, targetName: "Foo")
            let checksum = try Hashing.sha256Hex(await fileSystem.readFile(at: zipPath.absolutePath))
            let archivePath = cache.binaryArtifactArchivePath(url: artifactURL, checksum: checksum)
            try await fileSystem.makeDirectory(at: archivePath.deletingLastPathComponent().absolutePath, options: [.createTargetParentDirectories])
            try await fileSystem.write(
                await fileSystem.readFile(at: zipPath.absolutePath),
                to: archivePath
            )

            try await writeCachedManifest(
                binaryTargetManifest(name: "Foo", url: artifactURL, checksum: checksum),
                packageDir: cache.sourcePath(pin: pin)
            )
            try await writeCachedManifest(emptyManifest(), packageDir: package)

            let resolved = ResolvedPins(originHash: "origin", pins: [pin], version: 3)
            try await WorkspaceRestorer.restorePackage(
                scratchDir: scratch,
                packageDir: package,
                cache: cache,
                registryConfig: RegistryConfig(),
                resolved: resolved,
                progress: nil
            )
            try await WorkspaceRestorer.writeWorkspaceState(
                packageDir: package, scratchDir: scratch, resolved: resolved, disableSandbox: false
            )

            let statePath = scratch.appendingPathComponent("workspace-state.json")
            let state = try #require(
                try JSONSerialization.jsonObject(
                    with: await fileSystem.readFile(at: statePath.absolutePath))
                    as? [String: Any])
            let object = try #require(state["object"] as? [String: Any])
            let artifacts = try #require(object["artifacts"] as? [[String: Any]])
            let artifact = try #require(artifacts.first)
            let packageRef = try #require(artifact["packageRef"] as? [String: Any])
            let source = try #require(artifact["source"] as? [String: Any])
            let artifactPath = scratch
                .appendingPathComponent("artifacts/binary/Foo/Foo.xcframework")

            #expect(artifacts.count == 1)
            #expect(artifact["targetName"] as? String == "Foo")
            #expect(artifact["path"] as? String == artifactPath.path)
            #expect(packageRef["kind"] as? String == "remoteSourceControl")
            #expect(packageRef["location"] as? String == "https://github.com/example/binary.git")
            #expect(source["type"] as? String == "remote")
            #expect(source["url"] as? String == artifactURL)
            #expect(source["checksum"] as? String == checksum)
            #expect(try await fileSystem.exists(artifactPath.absolutePath))
        }
    }

    @Test
    func restorePackageRedownloadsRemoteBinaryArtifactWhenCachedArchiveChecksumMismatches()
        async throws
    {
        try await withTemporaryDirectory { root in
            let package = root.appendingPathComponent("Package")
            let scratch = root.appendingPathComponent("scratch")
            let cache = try await Cache(root: root.appendingPathComponent("cache"))
            let pin = ResolvedPin(
                identity: "binary",
                kind: "remoteSourceControl",
                location: "https://github.com/example/binary.git",
                state: ResolvedState(
                    branch: nil,
                    revision: "abcdef1234567890",
                    version: "1.0.0"
                )
            )
            let zipPath = try await makeXCFrameworkZip(root: root, targetName: "Foo")
            let artifactURL = zipPath.absoluteString
            let checksum = try Hashing.sha256Hex(await fileSystem.readFile(at: zipPath.absolutePath))
            let archivePath = cache.binaryArtifactArchivePath(url: artifactURL, checksum: checksum)
            try await fileSystem.makeDirectory(at: archivePath.deletingLastPathComponent().absolutePath, options: [.createTargetParentDirectories])
            try await fileSystem.write(
                Data("stale archive".utf8),
                to: archivePath
            )

            try await writeCachedManifest(
                binaryTargetManifest(name: "Foo", url: artifactURL, checksum: checksum),
                packageDir: cache.sourcePath(pin: pin)
            )
            try await writeCachedManifest(emptyManifest(), packageDir: package)

            let resolved = ResolvedPins(originHash: "origin", pins: [pin], version: 3)
            try await WorkspaceRestorer.restorePackage(
                scratchDir: scratch,
                packageDir: package,
                cache: cache,
                registryConfig: RegistryConfig(),
                resolved: resolved,
                progress: nil
            )

            let artifactPath = scratch
                .appendingPathComponent("artifacts/binary/Foo/Foo.xcframework")
            #expect(try await fileSystem.exists(archivePath.absolutePath))
            #expect(try Hashing.sha256Hex(fileAt: archivePath) == checksum)
            #expect(try await fileSystem.exists(artifactPath.absolutePath))
        }
    }

    @Test
    func restorePackageSerializesDuplicateLocalBinaryArchiveExtraction() async throws {
        try await withTemporaryDirectory { root in
            let package = root.appendingPathComponent("Package")
            let scratch = root.appendingPathComponent("scratch")
            let cache = try await Cache(root: root.appendingPathComponent("cache"))
            let zipPath = try await makeXCFrameworkZip(root: root, targetName: "Foo")
            let checksum = try Hashing.sha256Hex(await fileSystem.readFile(at: zipPath.absolutePath))
            try await writeCachedManifest(
                localBinaryTargetManifest(name: "Foo", path: "Foo.zip"),
                packageDir: package
            )
            try await fileSystem.write(
                await fileSystem.readFile(at: zipPath.absolutePath),
                to: package.appendingPathComponent("Foo.zip")
            )

            let resolved = ResolvedPins(originHash: "origin", pins: [], version: 3)
            async let first: Void = WorkspaceRestorer.restorePackage(
                scratchDir: scratch,
                packageDir: package,
                cache: cache,
                registryConfig: RegistryConfig(),
                resolved: resolved,
                progress: nil
            )
            async let second: Void = WorkspaceRestorer.restorePackage(
                scratchDir: scratch,
                packageDir: package,
                cache: cache,
                registryConfig: RegistryConfig(),
                resolved: resolved,
                progress: nil
            )
            _ = try await (first, second)

            let artifactPath = scratch
                .appendingPathComponent("artifacts/package/Foo/Foo.xcframework")
            let cachedArtifact = cache.binaryArtifactDirectory(
                identity: "package",
                targetName: "Foo",
                checksum: checksum
            )
            #expect(try await fileSystem.exists(artifactPath.absolutePath))
            #expect(try await fileSystem.exists(cachedArtifact.absolutePath))
        }
    }

    @Test
    func restorePackageIgnoresMacOSResourceForkShadowFramework() async throws {
        try await withTemporaryDirectory { root in
            let package = root.appendingPathComponent("Package")
            let scratch = root.appendingPathComponent("scratch")
            let cache = try await Cache(root: root.appendingPathComponent("cache"))
            let zipPath = try await makeXCFrameworkZip(
                root: root,
                targetName: "Foo",
                includeMacOSResourceFork: true
            )
            try await writeCachedManifest(
                localBinaryTargetManifest(name: "Foo", path: "Foo.zip"),
                packageDir: package
            )
            try await fileSystem.write(
                await fileSystem.readFile(at: zipPath.absolutePath),
                to: package.appendingPathComponent("Foo.zip")
            )

            let resolved = ResolvedPins(originHash: "origin", pins: [], version: 3)
            try await WorkspaceRestorer.restorePackage(
                scratchDir: scratch,
                packageDir: package,
                cache: cache,
                registryConfig: RegistryConfig(),
                resolved: resolved,
                progress: nil
            )
            try await WorkspaceRestorer.writeWorkspaceState(
                packageDir: package, scratchDir: scratch, resolved: resolved, disableSandbox: false
            )

            let artifactPath = scratch
                .appendingPathComponent("artifacts/package/Foo/Foo.xcframework")
            let shadowPath = scratch
                .appendingPathComponent("artifacts/package/Foo/__MACOSX")
            #expect(try await fileSystem.exists(artifactPath.absolutePath))
            #expect(try await fileSystem.exists(artifactPath.appendingPathComponent("Info.plist").absolutePath))
            #expect(try await !fileSystem.exists(shadowPath.absolutePath))

            let statePath = scratch.appendingPathComponent("workspace-state.json")
            let state = try #require(
                try JSONSerialization.jsonObject(
                    with: await fileSystem.readFile(at: statePath.absolutePath))
                    as? [String: Any])
            let object = try #require(state["object"] as? [String: Any])
            let artifacts = try #require(object["artifacts"] as? [[String: Any]])
            let artifact = try #require(artifacts.first)
            #expect(artifacts.count == 1)
            #expect(artifact["path"] as? String == artifactPath.path)
        }
    }

    private func makeXCFrameworkZip(
        root: URL,
        targetName: String,
        includeMacOSResourceFork: Bool = false
    ) async throws -> URL {
        let archiveRoot = root.appendingPathComponent("archive")
        let framework = archiveRoot.appendingPathComponent("\(targetName).xcframework")
        try await fileSystem.makeDirectory(at: framework.absolutePath, options: [.createTargetParentDirectories])
        try await fileSystem.atomicWrite(
            validXCFrameworkInfoPlist(),
            to: framework.appendingPathComponent("Info.plist")
        )
        let zipPath = root.appendingPathComponent("\(targetName).zip")
        var zipArguments = ["-qry", zipPath.path, "\(targetName).xcframework"]
        if includeMacOSResourceFork {
            let shadow = archiveRoot
                .appendingPathComponent("__MACOSX")
                .appendingPathComponent("\(targetName).xcframework")
            try await fileSystem.makeDirectory(
                at: shadow.absolutePath, options: [.createTargetParentDirectories]
            )
            try await fileSystem.atomicWrite(
                "shadow",
                to: shadow.appendingPathComponent("._Info.plist")
            )
            zipArguments.append("__MACOSX")
        }
        try await SystemProcess.run(
            "/usr/bin/zip",
            zipArguments,
            workingDirectory: archiveRoot
        )
        return zipPath
    }

    private func validXCFrameworkInfoPlist() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>AvailableLibraries</key>
          <array>
            <dict>
              <key>LibraryIdentifier</key>
              <string>macos-arm64</string>
              <key>LibraryPath</key>
              <string>Foo.framework</string>
              <key>SupportedArchitectures</key>
              <array>
                <string>arm64</string>
              </array>
              <key>SupportedPlatform</key>
              <string>macos</string>
            </dict>
          </array>
        </dict>
        </plist>
        """
    }

    private func binaryTargetManifest(name: String, url: String, checksum: String) -> [String: Any] {
        [
            "name": "BinaryPackage",
            "dependencies": [],
            "products": [],
            "targets": [
                [
                    "name": name,
                    "type": "binary",
                    "url": url,
                    "checksum": checksum,
                    "dependencies": [],
                    "exclude": [],
                    "resources": [],
                    "settings": [],
                ],
            ],
        ]
    }

    private func localBinaryTargetManifest(name: String, path: String) -> [String: Any] {
        [
            "name": "BinaryPackage",
            "dependencies": [],
            "products": [],
            "targets": [
                [
                    "name": name,
                    "type": "binary",
                    "path": path,
                    "dependencies": [],
                    "exclude": [],
                    "resources": [],
                    "settings": [],
                ],
            ],
        ]
    }
}
