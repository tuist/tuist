import Foundation

struct ResolvedPins: Codable, Sendable {
    var originHash: String?
    var pins: [ResolvedPin]
    var version: Int
    /// Invocation-local ownership, deliberately excluded from Package.resolved encoding.
    var nativeOwnedCheckouts: Set<String> = []

    init(originHash: String?, pins: [ResolvedPin], version: Int) {
        self.originHash = originHash
        self.pins = pins
        self.version = version
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        originHash = try container.decodeIfPresent(String.self, forKey: .originHash)
        if let pins = try container.decodeIfPresent([ResolvedPin].self, forKey: .pins) {
            version = try container.decode(Int.self, forKey: .version)
            self.pins = pins
        } else {
            let object = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .object)
            version = 3
            pins = try object.decode([ResolvedPin].self, forKey: .pins)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(originHash, forKey: .originHash)
        try container.encode(pins, forKey: .pins)
        try container.encode(version, forKey: .version)
    }

    private enum CodingKeys: String, CodingKey {
        case object
        case originHash
        case pins
        case version
    }

    func normalizedForResolvedFile(mirrors: MirrorConfig) -> ResolvedPins {
        var normalized = self
        normalized.pins = pins
            .map { $0.normalizedForResolvedFile(mirrors: mirrors) }
            .sorted {
                let lhsIdentity = $0.identity.lowercased()
                let rhsIdentity = $1.identity.lowercased()
                if lhsIdentity == rhsIdentity {
                    return $0.location.lowercased() < $1.location.lowercased()
                }
                return lhsIdentity < rhsIdentity
            }
        return normalized
    }
}

struct ResolvedPin: Codable, Equatable, Sendable {
    var identity: String
    var kind: String
    var location: String
    var state: ResolvedState
    /// The SCM URL the pin was originally declared as before
    /// `--replace-scm-with-registry` mapped it to a registry identity.
    /// SwiftPM records this so subsequent resolves can skip the registry
    /// identifier lookup; preserve it through the read/write roundtrip.
    var originalLocation: String?

    init(
        identity: String,
        kind: String,
        location: String,
        state: ResolvedState,
        originalLocation: String? = nil
    ) {
        self.identity = identity
        self.kind = kind
        self.location = location
        self.state = state
        self.originalLocation = originalLocation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let location = try container.decodeIfPresent(String.self, forKey: .location)
            ?? container.decodeIfPresent(String.self, forKey: .repositoryURL)
            ?? ""
        self.location = location
        identity = try container.decodeIfPresent(String.self, forKey: .identity)
            ?? Self.identity(
                package: try container.decodeIfPresent(String.self, forKey: .package),
                location: location
            )
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
            ?? Self.sourceControlKind(location: location)
        state = try container.decode(ResolvedState.self, forKey: .state)
        originalLocation = try container.decodeIfPresent(String.self, forKey: .originalLocation)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(identity, forKey: .identity)
        try container.encode(kind, forKey: .kind)
        try container.encode(location, forKey: .location)
        try container.encodeIfPresent(originalLocation, forKey: .originalLocation)
        try container.encode(state, forKey: .state)
    }

    static func identity(package: String?, location: String) -> String {
        if !location.isEmpty {
            let trimmed = location.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let withoutGit = trimmed.hasSuffix(".git") ? String(trimmed.dropLast(4)) : trimmed
            if let name = withoutGit.split(separator: "/").last {
                return String(name).lowercased()
            }
        }
        return package?.lowercased() ?? ""
    }

    private static func sourceControlKind(location: String) -> String {
        if location.hasPrefix("/") || URL(string: location)?.isFileURL == true {
            return "localSourceControl"
        }
        return "remoteSourceControl"
    }

    private enum CodingKeys: String, CodingKey {
        case identity
        case kind
        case location
        case originalLocation
        case package
        case repositoryURL
        case state
    }

    /// Keeps the location spelling SwiftPM recorded, so the lockfile is the same whichever tool
    /// wrote it. Comparisons and cache keys use `SourceControlLocations.canonicalLocation`.
    func normalizedForResolvedFile(mirrors: MirrorConfig) -> ResolvedPin {
        var normalized = self
        guard PinKind.isSourceControl(kind) else { return normalized }

        if let original = mirrors.mirroredOriginal(ofSourceControlLocation: location) {
            normalized.location = original
        }
        if kind != "localSourceControl",
           !location.hasPrefix("/"),
           URL(string: location)?.isFileURL != true
        {
            normalized.identity = identity.lowercased()
        }
        return normalized
    }

    func revision() throws -> String {
        guard let revision = state.revision else {
            throw ToolError.message("\(identity) does not have a source-control revision")
        }
        return revision
    }

    func versionString() throws -> String {
        guard let version = state.version else {
            throw ToolError.message("\(identity) does not have a resolved version")
        }
        return version
    }
}

struct ResolvedState: Codable, Equatable, Sendable {
    var branch: String?
    var revision: String?
    var version: String?
}

enum ResolvedFile {
    static func readIfCurrent(packageDir: URL) async throws -> ResolvedPins? {
        let path = packageDir.appendingPathComponent("Package.resolved")
        guard try await fileSystem.exists(path.absolutePath) else { return nil }

        let resolved = try await read(packageDir: packageDir)
        guard let originHash = resolved.originHash else { return nil }
        guard try originHash == (await packageOriginHash(packageDir: packageDir)) else {
            return nil
        }
        return resolved
    }

    static func read(packageDir: URL) async throws -> ResolvedPins {
        let data = try await fileSystem.readFile(
            at: packageDir.appendingPathComponent("Package.resolved").absolutePath)
        return try JSONDecoder().decode(ResolvedPins.self, from: data)
    }

    static func write(packageDir: URL, resolved: ResolvedPins, mirrors: MirrorConfig) async throws {
        let path = packageDir.appendingPathComponent("Package.resolved")
        if resolved.pins.isEmpty {
            try await fileSystem.removePath(path)
            return
        }
        let resolved = resolved.normalizedForResolvedFile(mirrors: mirrors)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(resolved) + Data("\n".utf8)
        let resolvedPath = try path.absolutePath
        // Skip the rewrite only when we can confirm the on-disk bytes already
        // match. A read failure (permissions, transient IO) must fall through
        // to `atomicWrite`, which replaces via a temp sibling, rather than
        // surface as an error the way an unconditional read would.
        if try await fileSystem.exists(resolvedPath),
           let existing = try? await fileSystem.readFile(at: resolvedPath),
           existing == data
        {
            return
        }
        try await fileSystem.atomicWrite(data, to: path)
    }

    static func print(_ resolved: ResolvedPins) {
        for pin in resolved.pins {
            if PinKind.isRegistry(pin.kind) {
                Swift.print("\(pin.identity) \(pin.state.version ?? "<unknown>") registry")
            } else if let version = pin.state.version {
                Swift.print(
                    "\(pin.identity) \(version) \(pin.state.revision ?? "<unknown>") \(pin.location)"
                )
            } else {
                Swift.print("\(pin.identity) \(pin.state.revision ?? "<unknown>") \(pin.location)")
            }
        }
    }

    static func packageOriginHash(packageDir: URL) async throws -> String {
        try Hashing.sha256Hex(
            await fileSystem.readFile(
                at: packageDir.appendingPathComponent("Package.swift").absolutePath))
    }
}

enum PinKind {
    static func isSourceControl(_ kind: String) -> Bool {
        kind == "remoteSourceControl" || kind == "localSourceControl" || kind == "sourceControl"
    }

    static func isRegistry(_ kind: String) -> Bool {
        kind == "registry"
    }

    /// SwiftPM names a checkout after the repository it clones, which is the mirror when one
    /// applies.
    static func checkoutDirectoryName(_ pin: ResolvedPin, mirrors: MirrorConfig) -> String {
        let trimmed = mirrors.effectiveLocation(of: pin).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let withoutGit = trimmed.hasSuffix(".git") ? String(trimmed.dropLast(4)) : trimmed
        let name = withoutGit.split(separator: "/").last.map(String.init).flatMap {
            $0.isEmpty ? nil : $0
        }
            ?? pin.identity
        return SafePathComponent.make(name)
    }

    static func registryIdentityParts(_ identity: String) throws -> (String, String) {
        let parts = identity.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            throw ToolError.message("\(identity) is not a scoped registry package identity")
        }
        return (parts[0], parts[1])
    }

    static func registryDownloadSubpath(_ pin: ResolvedPin) throws -> String {
        let (scope, name) = try PinKind.registryIdentityParts(pin.identity)
        return try [
            SafePathComponent.make(scope),
            SafePathComponent.make(name),
            SafePathComponent.make(pin.versionString()),
        ].joined(separator: "/")
    }
}

/// Where the toolchain's SwiftPM keeps registry packages below `registry/downloads`. A restore
/// lays them out the same way, so a workspace does not depend on whether SwifterPM or native
/// SwiftPM fetched it: generated projects, and Tuist's binary-cache keys with them, contain
/// these paths.
///
/// SwiftPM 6.4.2 moved each registry's downloads into a `<host>-<hash>` directory
/// (swiftlang/swift-package-manager#10573), and #10769 lengthened the hash from 8 to 32
/// hexadecimal characters on the 6.4.x branch after 6.4.3 and on 6.5. Earlier releases use
/// `<scope>/<name>/<version>`.
enum RegistryDownloadLayout: Equatable, Sendable {
    case unscoped
    case registryScoped(hashLength: Int)

    /// The layout of the SwiftPM that printed `output` (`swift --version`), or `nil` for a
    /// version it does not name, such as a development snapshot's `6.4-dev`.
    static func forSwiftVersion(_ output: String) -> RegistryDownloadLayout? {
        for marker in ["Apple Swift version ", "Swift version "] {
            guard let range = output.range(of: marker) else { continue }
            let rest = output[range.upperBound...]
            let number = rest.prefix(while: { $0.isNumber || $0 == "." })
            guard !rest.dropFirst(number.count).hasPrefix("-") else { return nil }
            let components = number.split(separator: ".").compactMap { Int($0) }
            guard components.count >= 2 else { return nil }
            let version = (components[0], components[1], components.count > 2 ? components[2] : 0)
            if version < (6, 4, 2) { return .unscoped }
            if version < (6, 4, 4) { return .registryScoped(hashLength: 8) }
            return .registryScoped(hashLength: 32)
        }
        return nil
    }

    /// SwiftPM's `Registry.storageKey`.
    static func storageKey(registryURL: URL, hashLength: Int) -> String {
        let canonical = CanonicalPackageURL(registryURL.absoluteString)
        let hash = String(Hashing.stable("\(canonical.description)_\(canonical.scheme ?? "")").prefix(hashLength))
        guard let host = registryURL.host?.lowercased(), host.utf8.count <= 32 else { return hash }
        return "\(host)-\(hash)"
    }

    func subpath(for pin: ResolvedPin, registryConfig: RegistryConfig) throws -> String {
        let subpath = try PinKind.registryDownloadSubpath(pin)
        guard case let .registryScoped(hashLength) = self else { return subpath }
        let registryURL = try registryConfig.registryURL(for: pin.identity)
        return "\(Self.storageKey(registryURL: registryURL, hashLength: hashLength))/\(subpath)"
    }

    /// The toolchain and registry configuration of one invocation, probed once when the first
    /// registry path is needed.
    actor Context {
        private let probe: @Sendable () async throws -> (RegistryDownloadLayout?, RegistryConfig)
        private var result: Task<(RegistryDownloadLayout, RegistryConfig)?, Never>?

        init(probe: @escaping @Sendable () async throws -> (RegistryDownloadLayout?, RegistryConfig)) {
            self.probe = probe
        }

        init(packageDirectory: URL, registryConfigurationPath: URL?, defaultRegistryURL: String?) {
            self.init {
                // Native resolution runs the `swift` on PATH with the resolution environment.
                let version = try await SystemProcess.run(
                    "swift", ["--version"], customEnvironment: Environment.resolution
                )
                let config = try await RegistryConfig.load(
                    packageDir: packageDirectory, configPath: registryConfigurationPath,
                    defaultRegistryURL: defaultRegistryURL
                )
                return (RegistryDownloadLayout.forSwiftVersion(version.stdoutString), config)
            }
        }

        /// `nil` when the toolchain or the configuration cannot be read, or the version is unknown.
        func value() async -> (RegistryDownloadLayout, RegistryConfig)? {
            if let result { return await result.value }
            let probe = probe
            let result = Task { () -> (RegistryDownloadLayout, RegistryConfig)? in
                guard let probed = try? await probe(), let layout = probed.0 else { return nil }
                return (layout, probed.1)
            }
            self.result = result
            return await result.value
        }
    }

    @TaskLocal static var context: Context?

    static func withContext<T>(
        packageDirectory: URL,
        registryConfigurationPath: URL?,
        defaultRegistryURL: String?,
        operation: () async throws -> T
    ) async throws -> T {
        try await $context.withValue(
            Context(
                packageDirectory: packageDirectory.syntacticallyStandardizedFileURL,
                registryConfigurationPath: registryConfigurationPath,
                defaultRegistryURL: defaultRegistryURL
            ),
            operation: operation
        )
    }
}

/// SwiftPM's `CanonicalPackageURL`, which `Registry.storageKey` hashes.
struct CanonicalPackageURL {
    let description: String
    let scheme: String?

    init(_ string: String) {
        var description = string.precomposedStringWithCanonicalMapping.lowercased()
        let detectedScheme = Self.dropScheme(&description)
        var scheme = detectedScheme

        if let at = description.firstIndex(of: "@"),
           let slash = description.firstIndex(of: "/"), at < slash
        {
            let user = String(description[..<at].split(separator: ":", omittingEmptySubsequences: false).first ?? "")
            description.removeSubrange(...at)
            if let range = description.range(of: "/~/") {
                description.replaceSubrange(range, with: "/~\(user)/")
            }
            if user == "git", scheme == nil { scheme = "ssh" }
        }

        if let slash = description.firstIndex(of: "/"),
           let colon = description.firstIndex(of: ":"),
           let portEnd = description[description.index(after: colon)...].lastIndex(where: \.isASCIIDigit),
           portEnd <= slash
        {
            description.removeSubrange(colon ... portEnd)
        }
        if let index = description.firstIndex(of: "#") { description.removeSubrange(index...) }
        if let index = description.firstIndex(of: "?") { description.removeSubrange(index...) }

        if detectedScheme == nil || detectedScheme == "ssh",
           let colon = description.firstIndex(of: ":"),
           description.firstIndex(of: "/").map({ colon < $0 }) ?? true
        {
            description.replaceSubrange(colon ... colon, with: "/")
        }

        var components = description.split(separator: "/").map { $0.removingPercentEncoding ?? String($0) }
        var last = components.popLast() ?? ""
        if last.hasSuffix(".git") { last.removeLast(4) }
        components.append(last)
        description = components.joined(separator: "/")

        if detectedScheme == "file" || string.first == "/" {
            scheme = "file"
            description.insert("/", at: description.startIndex)
        }
        self.description = description
        self.scheme = scheme
    }

    private static func dropScheme(_ string: inout String) -> String? {
        guard let delimiter = string.range(of: "://"),
              string.first?.isLetter == true,
              string[..<delimiter.lowerBound].allSatisfy({
                  $0.isLetter || $0.isASCIIDigit || $0 == "+" || $0 == "-" || $0 == "."
              })
        else { return nil }
        let scheme = String(string[..<delimiter.lowerBound])
        string.removeSubrange(..<delimiter.upperBound)
        return scheme
    }
}

extension Character {
    fileprivate var isASCIIDigit: Bool { ("0" ... "9").contains(self) }
}

struct RegistryDownloadPaths: Sendable {
    private var subpaths: [String: String] = [:]

    init(pins: [ResolvedPin], scratchDir: URL) async throws {
        let registryPins = Dictionary(uniqueKeysWithValues: pins.filter {
            PinKind.isRegistry($0.kind)
        }.map { ($0.identity.lowercased(), $0) })
        guard !registryPins.isEmpty else { return }

        // A known toolchain decides every path, replacing the ones an earlier SwifterPM
        // recorded in its own layout. Pins it cannot place keep the recorded location.
        if case let (layout, config)? = await RegistryDownloadLayout.context?.value() {
            for (identity, pin) in registryPins {
                subpaths[identity] = try? layout.subpath(for: pin, registryConfig: config)
            }
        }

        let statePath = scratchDir.appendingPathComponent("workspace-state.json")
        if try await fileSystem.exists(statePath.absolutePath) {
            let workspace = try JSONSerialization.jsonObject(
                with: await fileSystem.readFile(at: statePath.absolutePath)
            ) as? [String: Any]
            let object = workspace?["object"] as? [String: Any]
            let dependencies = object?["dependencies"] as? [[String: Any]] ?? []
            for dependency in dependencies {
                let ref = dependency["packageRef"] as? [String: Any]
                let state = dependency["state"] as? [String: Any]
                guard ref?["kind"] as? String == "registry",
                      let identity = ref?["identity"] as? String,
                      let pin = registryPins[identity.lowercased()],
                      subpaths[identity.lowercased()] == nil,
                      state?["name"] as? String == "registryDownload",
                      state?["version"] as? String == pin.state.version,
                      let subpath = dependency["subpath"] as? String
                else { continue }

                guard !subpath.isEmpty, !subpath.hasPrefix("/"), !subpath.split(separator: "/").contains("..") else {
                    throw ToolError.message("invalid registry download subpath for \(pin.identity): \(subpath)")
                }
                // Without a known toolchain, the location native SwiftPM recorded is the
                // only reliable account of its layout.
                subpaths[pin.identity.lowercased()] = subpath
            }
        }
    }

    func subpath(for pin: ResolvedPin) throws -> String {
        try subpaths[pin.identity.lowercased()] ?? PinKind.registryDownloadSubpath(pin)
    }
}
