import Foundation
import Path

/// Records native forced-lockfile validations that passed, keyed by everything SwiftPM's verdict
/// depends on, so an identical install, in this or another scratch directory, can reuse the verdict
/// instead of loading the whole graph again.
///
/// A validation is recorded only when SwiftPM left the prebuilts in the workspace state as
/// SwifterPM wrote them: SwiftPM records prebuilts during validation, which restoration cannot do.
enum ResolvedFileValidation {
    static func key(
        packageDir: URL,
        scratchDir: URL,
        registryConfigurationPath: URL?,
        defaultRegistryURL: String?,
        disableSandbox: Bool,
        scmToRegistryTransformation: SCMToRegistryTransformation
    ) async -> String? {
        do {
            let toolchain = try await (ManifestCache.toolchain ?? ManifestCache.ToolchainIdentity()).value()
            var inputs = [
                "schema": "1",
                "swifterpm": swifterpmVersion,
                "toolchain": toolchain,
                "environment": await ManifestEnvironmentFingerprint.current(packageDir: packageDir),
                "root": packageDir.standardizedFileURL.lastPathComponent,
                "manifests": try await manifestDigest(packageDir: packageDir),
                "Package.resolved": try await Hashing.sha256Hex(
                    fileSystem.readFile(at: packageDir.appendingPathComponent("Package.resolved").absolutePath)
                ),
                "defaultRegistryURL": defaultRegistryURL ?? "",
                "disableSandbox": String(disableSandbox),
                "scmToRegistryTransformation": String(describing: scmToRegistryTransformation),
                "prebuilts": try await prebuiltsDigest(scratchDir: scratchDir),
            ]
            for (name, file) in configurationFiles(packageDir: packageDir, configPath: registryConfigurationPath) {
                if let data = try? await fileSystem.readFile(at: file.absolutePath) {
                    inputs["configuration:\(name)"] = Hashing.sha256Hex(data)
                }
            }
            // Local packages are not pinned, so their manifests are inputs too. They are keyed by
            // their location relative to the root, which is the same in every checkout.
            let rootManifest = try await ManifestLoader.dumpPackage(packageDir: packageDir, disableSandbox: disableSandbox)
            let root = try PathCanonicalizer.realpath(packageDir).absolutePath
            for localPackage in try await ManifestFileSystemDependencyGraph.collect(
                rootPackageDir: packageDir, rootManifest: rootManifest, disableSandbox: disableSandbox
            ) {
                let location = try PathCanonicalizer.realpath(localPackage.packagePath).absolutePath.relative(to: root).pathString
                inputs["local:\(location)"] = try await manifestDigest(packageDir: localPackage.packagePath)
            }
            return ManifestEnvironmentFingerprint.digest(for: inputs)
        } catch {
            return nil
        }
    }

    static func isRecorded(key: String, cacheDir: URL) async -> Bool {
        (try? await fileSystem.exists(recordPath(key: key, cacheDir: cacheDir).absolutePath)) ?? false
    }

    static func record(key: String, cacheDir: URL) async {
        try? await fileSystem.atomicWrite(Data(), to: recordPath(key: key, cacheDir: cacheDir))
    }

    static func prebuiltsDigest(scratchDir: URL) async throws -> String {
        let prebuilts = try await WorkspaceRestorer.existingWorkspacePrebuilts(scratchDir: scratchDir).map {
            [
                $0["identity"] as? String ?? "",
                $0["version"] as? String ?? "",
                $0["libraryName"] as? String ?? "",
                ($0["path"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } ?? "",
            ].joined(separator: "\u{0}")
        }
        return Hashing.sha256Hex(Data(prebuilts.sorted().joined(separator: "\n").utf8))
    }

    private static func recordPath(key: String, cacheDir: URL) -> URL {
        cacheDir.appendingPathComponent("validations").appendingPathComponent(key)
    }

    private static func manifestDigest(packageDir: URL) async throws -> String {
        var manifests: [String: String] = [:]
        for manifest in try await ManifestCache.manifestCandidates(packageDir: packageDir) {
            manifests[manifest.lastPathComponent] = try await Hashing.sha256Hex(fileSystem.readFile(at: manifest.absolutePath))
        }
        return ManifestEnvironmentFingerprint.digest(for: manifests)
    }

    /// The registry and mirror configuration native resolution reads.
    private static func configurationFiles(packageDir: URL, configPath: URL?) -> [(String, URL)] {
        var files = [
            ("package-registries", packageDir.appendingPathComponent(".swiftpm/configuration/registries.json")),
        ]
        if let home = Environment.current["HOME"] {
            files.append((
                "user-registries",
                URL(fileURLWithPath: home).appendingPathComponent(".swiftpm/configuration/registries.json")
            ))
        }
        if let configPath {
            files.append(("config-registries", configPath.appendingPathComponent("registries.json")))
            files.append(("config-mirrors", configPath.appendingPathComponent("mirrors.json")))
        }
        return files
    }
}
