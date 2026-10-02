import Foundation

/// The dependency mirrors configured with `swift package config set-mirror`, loaded the way
/// SwiftPM loads them: the package's own configuration applies as a whole when it has any
/// entry, otherwise the shared one does, and a location is mirrored only on an exact match.
struct MirrorConfig: Sendable {
    private let mirrors: [String: String]
    /// The mirrored locations keyed by `SourceControlLocations.canonicalResolvedFileLocation`.
    /// SwifterPM used to write GitHub and GitLab pin locations into that form (without `.git`,
    /// for example), so a pin in such a Package.resolved does not match the location the mirror
    /// was configured for.
    private let canonicalSourceControlOriginals: [String: String]

    init(_ mirrors: [String: String] = [:]) {
        self.mirrors = mirrors
        canonicalSourceControlOriginals = Dictionary(
            mirrors.keys.sorted().map { (SourceControlLocations.canonicalResolvedFileLocation($0), $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    static func load(packageDir: URL, configPath: URL?) async throws -> MirrorConfig {
        let environment = Environment.current
        let localPath: URL
        if let customPath = environment["SWIFTPM_MIRROR_CONFIG"] {
            guard customPath.hasPrefix("/") else {
                throw ToolError.message("SWIFTPM_MIRROR_CONFIG must be an absolute path: \(customPath)")
            }
            localPath = URL(fileURLWithPath: customPath)
        } else {
            localPath = packageDir.appendingPathComponent(".swiftpm/configuration/mirrors.json")
        }
        let local = try await mirrors(at: localPath)
        if !local.isEmpty {
            return MirrorConfig(local)
        }
        guard let sharedPath = try await sharedMirrorsPath(configPath: configPath, environment: environment)
        else {
            return MirrorConfig()
        }
        return MirrorConfig(try await mirrors(at: sharedPath))
    }

    var isEmpty: Bool {
        mirrors.isEmpty
    }

    func effectiveLocation(for location: String) -> String {
        mirrors[location] ?? location
    }

    /// Where SwiftPM fetches a pin from. Package.resolved records the original location of a
    /// source-control pin and SwiftPM maps it through the mirrors when loading the file, so
    /// checkouts and `workspace-state.json` follow the mirror. Registry pins already carry the
    /// identity SwiftPM resolved after mirroring.
    func effectiveLocation(of pin: ResolvedPin) -> String {
        PinKind.isSourceControl(pin.kind) ? effectiveSourceControlLocation(for: pin.location) : pin.location
    }

    /// The location a mirror was configured for when one applies to the source-control
    /// `location`. SwiftPM records it verbatim in Package.resolved and only maps a pin whose
    /// location matches it exactly, so rewriting it would make SwiftPM fetch the original.
    func mirroredOriginal(ofSourceControlLocation location: String) -> String? {
        if mirrors[location] != nil { return location }
        return canonicalSourceControlOriginals[SourceControlLocations.canonicalResolvedFileLocation(location)]
    }

    private func effectiveSourceControlLocation(for location: String) -> String {
        mirroredOriginal(ofSourceControlLocation: location).flatMap { mirrors[$0] } ?? location
    }

    /// The identity SwiftPM gives a manifest dependency once mirrors apply. `dump-package`
    /// already maps the mirrors it can see, in which case this is the identity it reported.
    func identity(of dependency: ManifestDependency) -> String {
        let location = dependency.kind == .registry ? dependency.identity : dependency.location
        let effective = dependency.kind == .registry
            ? effectiveLocation(for: location)
            : effectiveSourceControlLocation(for: location)
        guard effective != location else { return dependency.identity.lowercased() }
        return Self.identity(forLocation: effective)
    }

    /// False when SwiftPM would not use `pin` as recorded because the mirrors now give its
    /// location another identity: a mirror was added, changed or removed, or maps the location
    /// to a registry identity. SwiftPM then resolves again and rewrites the pin.
    func isConsistent(with pin: ResolvedPin) -> Bool {
        if PinKind.isRegistry(pin.kind) {
            return effectiveLocation(for: pin.identity) == pin.identity
        }
        guard PinKind.isSourceControl(pin.kind) else { return true }
        let effective = effectiveSourceControlLocation(for: pin.location)
        // `--use-registry-identity-for-scm` names a source-control pin after its registry
        // identity, which cannot be derived from the location.
        if effective == pin.location, Self.isRegistryIdentity(pin.identity) {
            return true
        }
        return !Self.isRegistryIdentity(effective)
            && Self.identity(forLocation: effective) == pin.identity.lowercased()
    }

    /// False when a dependency the mirrors resolve to a registry identity has no pin under that
    /// identity. A registry pin records the identity after mirroring, so a mirror changed since
    /// the pin was written can only be noticed from the dependency's side.
    func registryDependenciesArePinned(_ dependencies: [ManifestDependency], by pins: [ResolvedPin]) -> Bool {
        let pinned = Set(pins.map { $0.identity.lowercased() })
        return dependencies.allSatisfy { dependency in
            let identity = identity(of: dependency)
            return !Self.isRegistryIdentity(identity) || pinned.contains(identity)
        }
    }

    private static func identity(forLocation location: String) -> String {
        isRegistryIdentity(location)
            ? location.lowercased()
            : ResolvedPin.identity(package: nil, location: location)
    }

    /// `PackageIdentity.isRegistry`: a scope of up to 39 alphanumerics and hyphens and a name of
    /// up to 100 alphanumerics, hyphens and underscores, joined by a dot. Hyphens and
    /// underscores may not lead, trail or repeat.
    static func isRegistryIdentity(_ location: String) -> Bool {
        let parts = location.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else { return false }
        return isValidRegistryComponent(parts[0], maxLength: 39, punctuation: ["-"])
            && isValidRegistryComponent(parts[1], maxLength: 100, punctuation: ["-", "_"])
    }

    private static func isValidRegistryComponent(
        _ component: Substring,
        maxLength: Int,
        punctuation: Set<Character>
    ) -> Bool {
        guard !component.isEmpty, component.count <= maxLength else { return false }
        var previousIsPunctuation = true
        for character in component {
            if punctuation.contains(character) {
                guard !previousIsPunctuation else { return false }
                previousIsPunctuation = true
            } else {
                guard character.isASCII, character.isLetter || character.isNumber else { return false }
                previousIsPunctuation = false
            }
        }
        return !previousIsPunctuation
    }

    private static func mirrors(at path: URL) async throws -> [String: String] {
        guard try await fileSystem.exists(path.absolutePath) else { return [:] }
        let data = try await fileSystem.readFile(at: path.absolutePath)
        let storage: Storage
        do {
            storage = try JSONDecoder().decode(Storage.self, from: data)
        } catch {
            throw ToolError.message("invalid mirrors configuration at \(path.path): \(error)")
        }
        return Dictionary(
            storage.object.map { ($0.original, $0.mirror) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// `--config-path` names SwiftPM's shared configuration directory. SwifterPM also accepts a
    /// path to `registries.json` there, in which case mirrors live next to it.
    private static func sharedMirrorsPath(
        configPath: URL?,
        environment: [String: String]
    ) async throws -> URL? {
        if let configPath {
            if try await fileSystem.exists(configPath.absolutePath, isDirectory: false) {
                return configPath.deletingLastPathComponent().appendingPathComponent("mirrors.json")
            }
            return configPath.appendingPathComponent("mirrors.json")
        }
        return environment["HOME"].map {
            URL(fileURLWithPath: $0).appendingPathComponent(".swiftpm/configuration/mirrors.json")
        }
    }

    private struct Storage: Decodable {
        struct Mirror: Decodable {
            let original: String
            let mirror: String
        }

        let object: [Mirror]
    }
}
