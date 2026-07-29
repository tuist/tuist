import Foundation
import Testing
@testable import SwifterPMCore

struct PackageInfoCacheTests {
    @Test
    func writePackageInfoCacheWritesRootIndexFromCachedManifest() async throws {
        try await withTemporaryDirectory { root in
            let package = root.appendingPathComponent("Package")
            let scratch = root.appendingPathComponent("scratch")
            let cacheDir = root.appendingPathComponent("package-info")
            try await writeCachedManifest(emptyManifest(), packageDir: package)

            try await PackageInfoCacheWriter.write(
                packageDir: package,
                scratchDir: scratch,
                resolved: ResolvedPins(originHash: "origin", pins: [], version: 3),
                cacheDir: cacheDir,
                disableSandbox: false,
                quiet: true
            )

            let indexPath = cacheDir.appendingPathComponent("index.json")
            let rootPath = cacheDir.appendingPathComponent("root.json")
            #expect(try await fileSystem.exists(indexPath.absolutePath))
            #expect(try await fileSystem.exists(rootPath.absolutePath))

            let index = try #require(
                JSONSerialization.jsonObject(
                    with: try await fileSystem.readFile(at: indexPath.absolutePath))
                    as? [String: Any])
            #expect(index["schema_version"] as? Int == 1)
            #expect((index["packages"] as? [[String: Any]])?.isEmpty == true)

            let rootEntry = try #require(index["root"] as? [String: Any])
            #expect(rootEntry["identity"] as? String == "root")
            #expect(rootEntry["revision"] as? String == "origin")
        }
    }

    @Test
    func writePackageInfoCacheReusesFreshRootPackageInfo() async throws {
        try await withTemporaryDirectory { root in
            let package = root.appendingPathComponent("Package")
            let scratch = root.appendingPathComponent("scratch")
            let cacheDir = root.appendingPathComponent("package-info")
            try await writeInvalidManifest(packageDir: package)

            try await Task.sleep(nanoseconds: 10_000_000)
            try await fileSystem.atomicWrite(
                try JSONFormatter.prettyData(emptyManifest(name: "CachedRoot")),
                to: cacheDir.appendingPathComponent("root.json"))

            try await PackageInfoCacheWriter.write(
                packageDir: package,
                scratchDir: scratch,
                resolved: ResolvedPins(originHash: "origin", pins: [], version: 3),
                cacheDir: cacheDir,
                disableSandbox: false,
                quiet: true
            )

            let rootInfo = try #require(
                JSONSerialization.jsonObject(
                    with: try await fileSystem.readFile(at: cacheDir.appendingPathComponent("root.json").absolutePath))
                    as? [String: Any])
            #expect(rootInfo["name"] as? String == "CachedRoot")
            #expect(
                try await fileSystem.exists(ManifestLoader.cacheFilePath(packageDir: package).absolutePath) == false)
        }
    }

    @Test
    func writePackageInfoCacheReusesFreshDependencyPackageInfo() async throws {
        try await withTemporaryDirectory { root in
            let package = root.appendingPathComponent("Package")
            let scratch = root.appendingPathComponent("scratch")
            let cacheDir = root.appendingPathComponent("package-info")
            try await writeCachedManifest(emptyManifest(), packageDir: package)

            let pin = ResolvedPin(
                identity: "foo",
                kind: "remoteSourceControl",
                location: "https://github.com/example/foo.git",
                state: ResolvedState(branch: nil, revision: "abcdef1234567890", version: "1.2.3")
            )
            let checkout = scratch.appendingPathComponent("checkouts/foo")
            try await writeInvalidManifest(packageDir: checkout)

            try await Task.sleep(nanoseconds: 10_000_000)
            let packageInfoPath =
                cacheDir
                .appendingPathComponent("packages")
                .appendingPathComponent("foo-\(entryHashForTest(pin)).json")
            try await fileSystem.atomicWrite(
                try JSONFormatter.prettyData(emptyManifest(name: "CachedDependency")),
                to: packageInfoPath)

            try await PackageInfoCacheWriter.write(
                packageDir: package,
                scratchDir: scratch,
                resolved: ResolvedPins(originHash: "origin", pins: [pin], version: 3),
                cacheDir: cacheDir,
                disableSandbox: false,
                quiet: true
            )

            let dependencyInfo = try #require(
                JSONSerialization.jsonObject(
                    with: try await fileSystem.readFile(at: packageInfoPath.absolutePath))
                    as? [String: Any])
            #expect(dependencyInfo["name"] as? String == "CachedDependency")
            #expect(
                try await fileSystem.exists(ManifestLoader.cacheFilePath(packageDir: checkout).absolutePath) == false)
        }
    }

    @Test
    func writePackageInfoCacheRefreshesStalePackageInfo() async throws {
        try await withTemporaryDirectory { root in
            let package = root.appendingPathComponent("Package")
            let scratch = root.appendingPathComponent("scratch")
            let cacheDir = root.appendingPathComponent("package-info")
            try await fileSystem.atomicWrite(
                try JSONFormatter.prettyData(emptyManifest(name: "StaleRoot")),
                to: cacheDir.appendingPathComponent("root.json"))

            try await Task.sleep(nanoseconds: 10_000_000)
            try await writeCachedManifest(emptyManifest(name: "FreshRoot"), packageDir: package)

            try await PackageInfoCacheWriter.write(
                packageDir: package,
                scratchDir: scratch,
                resolved: ResolvedPins(originHash: "origin", pins: [], version: 3),
                cacheDir: cacheDir,
                disableSandbox: false,
                quiet: true
            )

            let rootInfo = try #require(
                JSONSerialization.jsonObject(
                    with: try await fileSystem.readFile(at: cacheDir.appendingPathComponent("root.json").absolutePath))
                    as? [String: Any])
            #expect(rootInfo["name"] as? String == "FreshRoot")
        }
    }

    @Test
    func writePackageInfoCacheIncludesLocalFileSystemDependencies() async throws {
        try await withTemporaryDirectory { root in
            let package = root.appendingPathComponent("Package")
            let scratch = root.appendingPathComponent("scratch")
            let cacheDir = root.appendingPathComponent("package-info")
            let localOne = package.appendingPathComponent("LocalOne")
            let localTwo = root.appendingPathComponent("LocalTwo")
            var manifest = emptyManifest()
            manifest["dependencies"] = [
                [
                    "fileSystem": [
                        [
                            "identity": "local-one",
                            "path": "LocalOne",
                        ],
                        [
                            "identity": "local-two",
                            "nameForTargetDependencyResolutionOnly": "LocalTwoProduct",
                            "path": localTwo.path,
                        ],
                    ]
                ]
            ]

            try await writeCachedManifest(manifest, packageDir: package)
            try await writeCachedManifest(emptyManifest(name: "LocalOne"), packageDir: localOne)
            try await writeCachedManifest(emptyManifest(name: "LocalTwo"), packageDir: localTwo)

            try await PackageInfoCacheWriter.write(
                packageDir: package,
                scratchDir: scratch,
                resolved: ResolvedPins(originHash: "origin", pins: [], version: 3),
                cacheDir: cacheDir,
                disableSandbox: false,
                quiet: true
            )

            let index = try #require(
                JSONSerialization.jsonObject(
                    with: try await fileSystem.readFile(at: cacheDir.appendingPathComponent("index.json").absolutePath))
                    as? [String: Any])
            let packages = try #require(index["packages"] as? [[String: Any]])

            #expect(
                packages.compactMap { $0["identity"] as? String } == [
                    "local-one", "local-two",
                ])
            #expect(
                packages.first?["package_path"] as? String
                    == PathCanonicalizer.realpath(localOne).path)
            for package in packages {
                let packageInfoPath = try #require(package["package_info_path"] as? String)
                #expect(try await fileSystem.exists(URL(fileURLWithPath: packageInfoPath).absolutePath))
            }
        }
    }

    @Test
    func writePackageInfoCacheIncludesTransitiveLocalFileSystemDependencies() async throws {
        try await withTemporaryDirectory { root in
            let package = root.appendingPathComponent("Package")
            let scratch = root.appendingPathComponent("scratch")
            let cacheDir = root.appendingPathComponent("package-info")
            let localOne = package.appendingPathComponent("LocalOne")
            let localTwo = package.appendingPathComponent("LocalTwo")
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

            try await PackageInfoCacheWriter.write(
                packageDir: package,
                scratchDir: scratch,
                resolved: ResolvedPins(originHash: "origin", pins: [], version: 3),
                cacheDir: cacheDir,
                disableSandbox: false,
                quiet: true
            )

            let index = try #require(
                JSONSerialization.jsonObject(
                    with: try await fileSystem.readFile(at: cacheDir.appendingPathComponent("index.json").absolutePath))
                    as? [String: Any])
            let packages = try #require(index["packages"] as? [[String: Any]])

            #expect(
                packages.compactMap { $0["identity"] as? String } == [
                    "local-one", "local-two",
                ])
        }
    }

    private func writeInvalidManifest(packageDir: URL) async throws {
        try await fileSystem.makeDirectory(at: packageDir.absolutePath, options: [.createTargetParentDirectories])
        try await fileSystem.atomicWrite(
            "not a valid Swift package manifest",
            to: packageDir.appendingPathComponent("Package.swift"))
    }

    private func entryHashForTest(_ pin: ResolvedPin) -> String {
        let input = "\(pin.location):\(pin.state.version ?? ""):\(pin.state.revision ?? "")"
        return String(Hashing.stable(input).prefix(16))
    }
}
