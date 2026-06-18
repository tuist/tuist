import Foundation

struct ResolvedPins: Codable, Sendable {
    var originHash: String?
    var pins: [ResolvedPin]
    var version: Int

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

    private static func identity(package: String?, location: String) -> String {
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

    static func write(packageDir: URL, resolved: ResolvedPins) async throws {
        let path = packageDir.appendingPathComponent("Package.resolved")
        if resolved.pins.isEmpty {
            try await fileSystem.removePath(path)
            return
        }
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

    static func checkoutDirectoryName(_ pin: ResolvedPin) -> String {
        let trimmed = pin.location.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
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
