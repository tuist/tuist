import Foundation
#if canImport(Security)
    import Security
#endif

struct RegistryConfig: Sendable {
    private var defaultRegistryURL: URL?
    private var scopedRegistryURLs: [String: URL] = [:]
    private var registryAuthentication: [String: RegistryAuthenticationType] = [:]

    static func load(packageDir: URL, configPath: URL?, defaultRegistryURL: String?) async throws
        -> RegistryConfig
    {
        var config = RegistryConfig()
        if let global = Self.globalRegistriesPath() {
            try await config.mergeFile(global)
        }
        try await config.mergeFile(
            packageDir.appendingPathComponent(".swiftpm/configuration/registries.json"))
        if let configPath {
            try await config.mergeFile(try await Self.registriesPath(fromConfigPath: configPath))
        }
        if let defaultRegistryURL {
            config.defaultRegistryURL = try Self.parseRegistryURL(defaultRegistryURL)
        }
        return config
    }

    /// Native SwiftPM replaces shared configuration with --config-path, then applies local overrides.
    static func loadForNativeResolution(packageDir: URL, configPath: URL?, defaultRegistryURL: String?) async throws
        -> RegistryConfig
    {
        var config = RegistryConfig()
        if let configPath {
            guard !(try await fileSystem.exists(configPath.absolutePath, isDirectory: false)) else {
                throw ToolError.message("native SwiftPM --config-path must name a directory, not a registries.json file")
            }
            try await config.mergeFile(configPath.appendingPathComponent("registries.json"), normalizesAuthenticationKeys: false)
        } else if let global = Self.globalRegistriesPath() {
            try await config.mergeFile(global, normalizesAuthenticationKeys: false)
        }
        try await config.mergeFile(
            packageDir.appendingPathComponent(".swiftpm/configuration/registries.json"), normalizesAuthenticationKeys: false
        )
        if let defaultRegistryURL {
            config.defaultRegistryURL = try Self.parseRegistryURL(defaultRegistryURL)
        }
        return config
    }

    var registryURLs: [URL] {
        Array(scopedRegistryURLs.values) + [defaultRegistryURL].compactMap { $0 }
    }

    func registryURL(for identity: String) throws -> URL {
        let (scope, _) = try PinKind.registryIdentityParts(identity)
        if let scoped = scopedRegistryURLs[scope] ?? scopedRegistryURLs[scope.lowercased()] {
            return scoped
        }
        if let defaultRegistryURL {
            return defaultRegistryURL
        }
        throw ToolError.message("no registry configured for '\(scope)' scope")
    }

    private mutating func mergeFile(_ path: URL, normalizesAuthenticationKeys: Bool = true) async throws {
        guard try await fileSystem.exists(path.absolutePath) else { return }
        guard let root = try JSONSerialization.jsonObject(
            with: try await fileSystem.readFile(at: path.absolutePath)) as? [String: Any],
            let registries = root["registries"] as? [String: Any]
        else {
            return
        }
        for (scope, value) in registries {
            guard let entry = value as? [String: Any],
                  let urlString = entry["url"] as? String
            else {
                continue
            }
            let url = try Self.parseRegistryURL(urlString)
            if scope == "[default]" {
                defaultRegistryURL = url
            } else {
                scopedRegistryURLs[scope.lowercased()] = url
            }
        }
        if let authentication = root["authentication"] as? [String: Any] {
            for (registry, value) in authentication {
                guard let entry = value as? [String: Any],
                      let typeString = entry["type"] as? String,
                      let type = RegistryAuthenticationType(rawValue: typeString)
                else {
                    continue
                }
                registryAuthentication[normalizesAuthenticationKeys ? registry.lowercased() : registry] = type
            }
        }
    }

    private static func parseRegistryURL(_ url: String) throws -> URL {
        guard let parsed = URL(string: url),
              parsed.scheme == "https" || (parsed.scheme == "http" && parsed.isLocalhost)
        else {
            throw ToolError.message("registry URL must use https: \(url)")
        }
        return parsed
    }

    private static func registriesPath(fromConfigPath configPath: URL) async throws -> URL {
        if try await fileSystem.exists(configPath.absolutePath, isDirectory: false) {
            return configPath
        }
        return configPath.appendingPathComponent("registries.json")
    }

    private static func globalRegistriesPath() -> URL? {
        Environment.current["HOME"].map {
            URL(fileURLWithPath: $0).appendingPathComponent(
                ".swiftpm/configuration/registries.json")
        }
    }

    fileprivate func containsOrigin(of url: URL) -> Bool {
        let registries = Array(scopedRegistryURLs.values) + [defaultRegistryURL].compactMap { $0 }
        return registries.contains {
            $0.scheme?.lowercased() == url.scheme?.lowercased()
                && $0.host?.lowercased() == url.host?.lowercased()
                && ($0.port ?? ($0.scheme == "https" ? 443 : 80))
                == (url.port ?? (url.scheme == "https" ? 443 : 80))
        }
    }

    func authenticationType(for registryURL: URL) -> RegistryAuthenticationType? {
        guard let host = registryURL.host?.lowercased() else { return nil }
        let key = [host, registryURL.port.map(String.init)].compactMap { $0 }.joined(separator: ":")
        return registryAuthentication[key]
    }
}

enum RegistryAuthenticationType: String, Sendable {
    case basic
    case token
}

struct RegistryCredential: Sendable {
    let user: String
    let password: String
}

enum RegistryAuthorization {
    static func header(
        for url: URL,
        registryConfig: RegistryConfig,
        keychain: (URL) async throws -> RegistryCredential? = { try await KeychainAuthorization.credential(for: $0) }
    ) async throws -> String? {
        let environment = Environment.current
        let token = nonEmpty(environment["SWIFTPM_REGISTRY_TOKEN"])
        let login = nonEmpty(environment["SWIFTPM_REGISTRY_LOGIN"])
        let password = nonEmpty(environment["SWIFTPM_REGISTRY_PASSWORD"])
        if token != nil || (login != nil && password != nil) {
            // Selecting the environment provider also excludes fallback for other origins.
            guard registryConfig.containsOrigin(of: url) else { return nil }
            let credential: RegistryCredential
            if let token {
                credential = RegistryCredential(user: "token", password: token)
            } else if let login, let password {
                credential = RegistryCredential(user: login, password: password)
            } else {
                return nil
            }
            return header(for: credential, url: url, registryConfig: registryConfig)
        }

        let netrc = Environment.netrc
        // SwiftPM's `--disable-keychain` intentionally leaves the registry keychain
        // provider in place — see `SwiftCommandState.getRegistryAuthorizationProvider`,
        // which ignores `options.security.keychain` and only honours `forceNetrc`. The
        // flag disables the keychain for binary artifact downloads (`HTTPAuthorization`)
        // and nothing else. Gating this call site as well would silently diverge from
        // `swift package resolve` on the same inputs.
        if let credential = try await prioritizedCredential(
            environmentNetrcIsConfigured: netrc.hasEnvironmentSource,
            environmentNetrc: netrc.credential(for: url, from: .environment),
            fileNetrc: netrc.credential(for: url, from: .file),
            usesKeychain: KeychainAuthorization.isSupported && !netrc.forcesNetrc,
            keychain: { try await keychain(url) }
        ) {
            return header(for: credential, url: url, registryConfig: registryConfig)
        }

        return nil
    }

    /// Registry auth selects one provider, unlike the HTTP composite: a missing
    /// host in inline data or a missing keychain item must not fall through to files.
    static func prioritizedCredential(
        environmentNetrcIsConfigured: Bool,
        environmentNetrc: RegistryCredential?,
        fileNetrc: RegistryCredential?,
        usesKeychain: Bool,
        keychain: () async throws -> RegistryCredential?
    ) async throws -> RegistryCredential? {
        if environmentNetrcIsConfigured { return environmentNetrc }
        if usesKeychain { return try await keychain() }
        return fileNetrc
    }

    static func header(
        for credential: RegistryCredential,
        url: URL,
        registryConfig: RegistryConfig
    ) -> String {
        switch registryConfig.authenticationType(for: url) {
        case .basic:
            return basicHeader(credential)
        case .token:
            return bearerHeader(credential.password)
        case nil:
            if credential.user == "token" {
                return bearerHeader(credential.password)
            }
            return basicHeader(credential)
        }
    }

    private static func basicHeader(_ credential: RegistryCredential) -> String {
        let token = Data("\(credential.user):\(credential.password)".utf8).base64EncodedString()
        return "Basic \(token)"
    }

    private static func bearerHeader(_ token: String) -> String {
        "Bearer \(token)"
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

actor KeychainCredentialCache {
    private var reads: [String: Task<RegistryCredential?, any Error>] = [:]

    func credential(
        for url: URL,
        read: @escaping @Sendable (URL) async throws -> RegistryCredential?
    ) async throws -> RegistryCredential? {
        let key = [url.scheme ?? "https", url.host?.lowercased() ?? "", url.port.map(String.init) ?? ""].joined(separator: ":")
        if let existing = reads[key] { return try await existing.value }
        let task = Task { try await read(url) }
        reads[key] = task
        return try await task.value
    }
}

enum KeychainAuthorization {
    static var isSupported: Bool {
        #if canImport(Security)
            true
        #else
            false
        #endif
    }

    static func credential(for url: URL) async throws -> RegistryCredential? {
        if let cache = Environment.keychainCredentials {
            return try await cache.credential(for: url) { try await uncachedCredential(for: $0) }
        }
        return try await uncachedCredential(for: url)
    }

    private static func uncachedCredential(for url: URL) async throws -> RegistryCredential? {
        #if canImport(Security)
            if Environment.isCI || isatty(STDIN_FILENO) == 0 {
                return try await KeychainCredentialReader.credential(for: url)
            }
            guard let searchQuery = query(for: url, includeData: false) else { return nil }
            var items: CFTypeRef?
            let status = SecItemCopyMatching(searchQuery as CFDictionary, &items)
            guard try lookupSucceeded(status, host: url.host), let existingItems = items as? [[String: Any]] else {
                return nil
            }
            let sortedItems = existingItems.sorted {
                switch (
                    $0[kSecAttrModificationDate as String] as? Date,
                    $1[kSecAttrModificationDate as String] as? Date
                ) {
                case (nil, nil):
                    return false
                case (_, nil):
                    return true
                case (nil, _):
                    return false
                case let (.some(left), .some(right)):
                    return left < right
                }
            }
            guard let item = sortedItems.last,
                  let created = item[kSecAttrCreationDate as String] as? Date,
                  var detailQuery = query(for: url, includeData: true)
            else {
                return nil
            }
            detailQuery[kSecAttrCreationDate as String] = created
            if let modified = item[kSecAttrModificationDate as String] as? Date {
                detailQuery[kSecAttrModificationDate as String] = modified
            }

            var detail: CFTypeRef?
            guard try lookupSucceeded(SecItemCopyMatching(detailQuery as CFDictionary, &detail), host: url.host),
                  let credential = detail as? [String: Any],
                  let account = credential[kSecAttrAccount as String] as? String,
                  let passwordData = credential[kSecValueData as String] as? Data
            else {
                return nil
            }
            return RegistryCredential(user: account, password: String(decoding: passwordData, as: UTF8.self))
        #else
            return nil
        #endif
    }

    static func httpCredential(
        for url: URL,
        read: (URL) async throws -> RegistryCredential? = { try await credential(for: $0) },
        warning: (String) -> Void = { FileHandle.standardError.write(Data("Warning: \($0)\n".utf8)) }
    ) async throws -> RegistryCredential? {
        do {
            return try await read(url)
        } catch {
            #if canImport(Security)
                if let failure = error as? AccessFailure {
                    warning("\(failure) Trying the HTTP download without keychain credentials.")
                    return nil
                }
            #endif
            // Reader startup and decoding errors must not block public downloads or
            // expose captured credential output through an arbitrary error message.
            warning(
                "keychain lookup failed for \(url.host ?? "the download host"). Trying the HTTP download without keychain credentials."
            )
            return nil
        }
    }

    #if canImport(Security)
        static func lookupSucceeded(_ status: OSStatus, host: String?) throws -> Bool {
            if status == errSecSuccess { return true }
            if status == errSecItemNotFound { return false }
            throw AccessFailure(status: status, host: host)
        }

        struct AccessFailure: Error, CustomStringConvertible {
            let status: OSStatus
            let host: String?

            var description: String {
                "cannot read keychain credentials for \(host ?? "the download host") (OSStatus \(status)). "
                    + "Unlock the keychain or use host-scoped netrc credentials. "
                    + "For headless use, prefer netrc; do not authorize the generic Swift interpreter just to grant Tuist access. For registries, pass --netrc --netrc-file <path> "
                    + "and configure the authentication type in registries.json."
            }
        }

        static func query(for url: URL, includeData: Bool) -> [String: Any]? {
            guard let host = url.host?.lowercased(), !host.isEmpty else { return nil }
            var query: [String: Any] = [
                kSecClass as String: kSecClassInternetPassword,
                kSecAttrProtocol as String: url.scheme == "http" ? kSecAttrProtocolHTTP : kSecAttrProtocolHTTPS,
                kSecAttrServer as String: host,
                kSecMatchLimit as String: includeData ? kSecMatchLimitOne : kSecMatchLimitAll,
                kSecReturnAttributes as String: true,
            ]
            if includeData {
                query[kSecReturnData as String] = true
            }
            if let port = url.port {
                query[kSecAttrPort as String] = port
            }
            return query
        }
    #endif
}

struct RegistrySourceArchive: Sendable {
    let registryURL: URL
    let checksum: String
}

enum RegistryClient {
    static func sourceArchive(
        registryConfig: RegistryConfig,
        identity: String,
        version: String
    ) async throws -> RegistrySourceArchive {
        let registryURL = try registryConfig.registryURL(for: identity)
        return RegistrySourceArchive(
            registryURL: registryURL,
            checksum: try await fetchSourceArchiveChecksum(
                registryURL: registryURL,
                identity: identity,
                version: version,
                registryConfig: registryConfig
            )
        )
    }

    static func downloadArchive(
        cache: Cache,
        registryConfig: RegistryConfig,
        registryURL: URL,
        identity: String,
        version: String,
        expectedChecksum: String,
        destination: URL
    ) async throws {
        let archivePath = cache.registryArchivePath(
            identity: identity,
            version: version,
            registryURL: registryURL.absoluteString,
            checksum: expectedChecksum
        )
        if try await !validCachedArchive(archivePath, expectedChecksum: expectedChecksum) {
            let lock = try await cache.lock(namespace: "registry-archives", key: archivePath.path)
            _ = lock
            if try await !validCachedArchive(archivePath, expectedChecksum: expectedChecksum) {
                try? await fileSystem.removePath(archivePath)
                let data = try await fetchRegistryArchive(
                    registryURL: registryURL,
                    identity: identity,
                    version: version,
                    registryConfig: registryConfig
                )
                let actual = Hashing.sha256Hex(data)
                guard actual.caseInsensitiveCompare(expectedChecksum) == .orderedSame else {
                    throw ToolError.message(
                        "\(identity) \(version) checksum mismatch: expected \(expectedChecksum), got \(actual)"
                    )
                }
                try await fileSystem.atomicWrite(data, to: archivePath)
            }
        }

        try await SystemProcess.run(
            "/usr/bin/unzip", ["-q", archivePath.path, "-d", destination.path]
        )
        try await fileSystem.flattenSingleDirectory(destination)
    }

    private static func validCachedArchive(_ archivePath: URL, expectedChecksum: String)
        async throws -> Bool
    {
        guard try await fileSystem.exists(archivePath.absolutePath) else {
            return false
        }
        let actual = try Hashing.sha256Hex(fileAt: archivePath)
        if actual.caseInsensitiveCompare(expectedChecksum) == .orderedSame {
            return true
        }
        try? await fileSystem.removePath(archivePath)
        return false
    }

    private static func fetchSourceArchiveChecksum(
        registryURL: URL,
        identity: String,
        version: String,
        registryConfig: RegistryConfig
    ) async throws -> String {
        struct ReleaseInfo: Decodable {
            struct Resource: Decodable {
                let name: String
                let type: String
                let checksum: String
            }

            let resources: [Resource]
        }
        let data = try await HTTPClient.data(
            url: try packageURL(registryURL: registryURL, identity: identity, version: version),
            headers: try await headers(
                accept: "application/vnd.swift.registry.v1+json",
                registryURL: registryURL,
                registryConfig: registryConfig
            )
        )
        let info = try JSONDecoder().decode(ReleaseInfo.self, from: data)
        guard let resource = info.resources.first(where: {
            $0.name == "source-archive" && $0.type == "application/zip"
        })
        else {
            throw ToolError.message(
                "\(identity) \(version) does not declare a source archive checksum")
        }
        return resource.checksum
    }

    private static func fetchRegistryArchive(
        registryURL: URL,
        identity: String,
        version: String,
        registryConfig: RegistryConfig
    )
        async throws -> Data
    {
        let (scope, name) = try PinKind.registryIdentityParts(identity)
        let url = registryURL.appendingPathComponents([scope, name, "\(version).zip"])
        return try await HTTPClient.data(
            url: url,
            headers: try await headers(
                accept: "application/vnd.swift.registry.v1+zip",
                registryURL: registryURL,
                registryConfig: registryConfig
            )
        )
    }

    private static func headers(
        accept: String,
        registryURL: URL,
        registryConfig: RegistryConfig
    ) async throws -> [String: String] {
        var headers = ["Accept": accept]
        if let authorization = try await RegistryAuthorization.header(
            for: registryURL, registryConfig: registryConfig
        ) {
            headers["Authorization"] = authorization
        }
        return headers
    }

    private static func packageURL(registryURL: URL, identity: String, version: String? = nil)
        throws
        -> URL
    {
        let (scope, name) = try PinKind.registryIdentityParts(identity)
        var components = [scope, name]
        if let version {
            components.append(version)
        }
        return registryURL.appendingPathComponents(components)
    }
}

extension URL {
    fileprivate var isLocalhost: Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}
