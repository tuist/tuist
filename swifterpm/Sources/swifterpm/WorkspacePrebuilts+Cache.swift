import Foundation

extension WorkspacePrebuilts {
    /// The packages native SwiftPM has prebuilts for, with the source-control locations it accepts for each
    /// (`Workspace.PrebuiltsManager.prebuiltPackages`). A location without the `.git` suffix matches as well.
    private static let prebuiltPackages: [String: Set<String>] = [
        "swift-syntax": [
            "https://github.com/swiftlang/swift-syntax.git",
            "https://github.com/apple/swift-syntax.git",
            "git@github.com:swiftlang/swift-syntax.git",
        ],
    ]

    /// Restores the prebuilts native SwiftPM left in the shared cache (`--cache-path`) for pins without an applicable
    /// entry, extracted and recorded the way a resolution would. Without this, the restoration path leaves those
    /// packages to build from source after a toolchain update, or in a fresh scratch directory, until the next native
    /// resolution. A prebuilt the cache does not hold is not fetched, and a broken cache entry leaves the package to
    /// build from source rather than failing the restore.
    ///
    /// SwiftPM verifies a manifest's signature before it caches it, so the cached copy is trusted like the cached
    /// sources; its archives still have to match the checksums it lists. Only macOS is covered: elsewhere SwiftPM
    /// ships the archives as tarballs.
    static func restoredFromCache(
        pins: [ResolvedPin],
        recorded: [[String: Any]],
        mirrors: MirrorConfig,
        scratchDir: URL,
        cacheDir: URL,
        name: () async throws -> String?
    ) async throws -> [[String: Any]] {
        #if os(macOS)
            let cache = cacheDir.appendingPathComponent("prebuilts")
            var candidates: [(identity: String, version: String, cached: URL)] = []
            for pin in pins {
                guard let identity = prebuiltPackageIdentity(of: pin, mirrors: mirrors),
                      let version = pin.state.version,
                      !recorded.contains(where: {
                          ($0["identity"] as? String)?.lowercased() == identity && $0["version"] as? String == version
                      })
                else { continue }
                let cached = cache.appendingPathComponent(identity).appendingPathComponent(version)
                // Probing the toolchain costs a compiler launch, so only do it when a manifest could match.
                let files = try await ignoringFailures { try await fileSystem.contentsOfDirectory(at: cached) }
                guard files?.contains(where: { $0.pathExtension == "json" }) == true else { continue }
                candidates.append((identity, version, cached))
            }
            let disabled = try await ignoringFailures {
                try await fileSystem.exists(cache.appendingPathComponent("noprebuilts").absolutePath)
            }
            // SwiftPM skips prebuilts altogether when the cache holds that marker.
            guard !candidates.isEmpty, disabled != true, let name = try await name() else { return [] }

            var restored: [[String: Any]] = []
            for candidate in candidates {
                let manifest = try await ignoringFailures {
                    try JSONDecoder().decode(
                        SignedManifest.self,
                        from: await fileSystem.readFile(
                            at: candidate.cached.appendingPathComponent("\(name).json").absolutePath
                        )
                    ).manifest
                }
                for library in manifest?.libraries ?? [] {
                    let artifactName = "\(name)-\(library.name)"
                    let artifact = scratchDir.appendingPathComponent("prebuilts")
                        .appendingPathComponent(candidate.identity)
                        .appendingPathComponent(candidate.version)
                        .appendingPathComponent(artifactName)
                    let archive = candidate.cached.appendingPathComponent("\(artifactName).zip")
                    // SwiftPM reuses an extracted directory as is.
                    let extracted = try await ignoringFailures {
                        try await WorkspaceRestorer.extractZip(
                            archive,
                            to: artifact,
                            isUsable: { try await fileSystem.exists($0.absolutePath) }
                        ) { _ in
                            guard try Hashing.sha256Hex(fileAt: archive).lowercased() == library.checksum.lowercased()
                            else { throw ToolError.message("\(archive.lastPathComponent) does not match its checksum") }
                        }
                    }
                    guard extracted != nil else { continue }
                    var entry: [String: Any] = [
                        "identity": candidate.identity,
                        "version": candidate.version,
                        "libraryName": library.name,
                        "path": artifact.path,
                        "checkoutPath": checkoutPath(scratchDir: scratchDir, identity: candidate.identity),
                        "products": library.products,
                        "cModules": [String](),
                    ]
                    if let includePath = library.includePath {
                        entry["includePath"] = includePath
                    }
                    restored.append(entry)
                }
            }
            return restored
        #else
            return []
        #endif
    }

    private static func prebuiltPackageIdentity(of pin: ResolvedPin, mirrors: MirrorConfig) -> String? {
        guard pin.kind == "remoteSourceControl" || pin.kind == "sourceControl",
              let locations = prebuiltPackages[pin.identity.lowercased()]
        else { return nil }
        // SwiftPM matches the location it fetches from, after mirrors apply.
        let location = mirrors.effectiveLocation(of: pin)
        let matches = locations.contains(location)
            || (!location.hasSuffix(".git") && locations.contains("\(location).git"))
        return matches ? pin.identity.lowercased() : nil
    }

    private struct SignedManifest: Decodable {
        struct Manifest: Decodable {
            let libraries: [Library]
        }

        struct Library: Decodable {
            let name: String
            let checksum: String
            let products: [String]
            let includePath: [String]?
        }

        let manifest: Manifest
    }

    /// `nil` when `operation` fails, except on cancellation.
    private static func ignoringFailures<T>(_ operation: () async throws -> T) async throws -> T? {
        do {
            return try await operation()
        } catch {
            try Task.checkCancellation()
            return nil
        }
    }
}
