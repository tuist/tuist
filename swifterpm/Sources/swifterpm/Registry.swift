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

    private mutating func mergeFile(_ path: URL) async throws {
        guard try await fileSystem.exists(path.absolutePath) else { return }
        guard
            let root = try JSONSerialization.jsonObject(
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
                registryAuthentication[registry.lowercased()] = type
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
        ProcessInfo.processInfo.environment["HOME"].map {
            URL(fileURLWithPath: $0).appendingPathComponent(
                ".swiftpm/configuration/registries.json")
        }
    }

    fileprivate func authenticationType(for registryURL: URL) -> RegistryAuthenticationType? {
        guard let host = registryURL.host?.lowercased() else { return nil }
        let key = [host, registryURL.port.map(String.init)].compactMap { $0 }.joined(separator: ":")
        return registryAuthentication[key]
    }
}

private enum RegistryAuthenticationType: String, Sendable {
    case basic
    case token
}

struct RegistryCredential: Sendable {
    let user: String
    let password: String
}

enum RegistryAuthorization {
    static func header(for url: URL, registryConfig: RegistryConfig) async -> String? {
        if let token = nonEmpty(ProcessInfo.processInfo.environment["SWIFTPM_REGISTRY_TOKEN"]) {
            return bearerHeader(token)
        }

        let environment = ProcessInfo.processInfo.environment
        if let login = nonEmpty(environment["SWIFTPM_REGISTRY_LOGIN"]),
           let password = nonEmpty(environment["SWIFTPM_REGISTRY_PASSWORD"])
        {
            return header(
                for: RegistryCredential(user: login, password: password),
                url: url,
                registryConfig: registryConfig
            )
        }

        if let netrcData = nonEmpty(environment["SWIFTPM_NETRC_DATA"]),
           let credential = RegistryNetrc(content: netrcData).credential(for: url)
        {
            return header(for: credential, url: url, registryConfig: registryConfig)
        }

        if let credential = await RegistryKeychain.credential(for: url) {
            return header(for: credential, url: url, registryConfig: registryConfig)
        }

        if let home = environment["HOME"] {
            let netrcPath = URL(fileURLWithPath: home).appendingPathComponent(".netrc")
            if let data = try? await fileSystem.readFile(at: netrcPath.absolutePath),
               let content = String(data: data, encoding: .utf8),
               let credential = RegistryNetrc(content: content).credential(for: url)
            {
                return header(for: credential, url: url, registryConfig: registryConfig)
            }
        }

        return nil
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

struct RegistryNetrc {
    private let machines: [Machine]

    init(content: String) {
        machines = Self.parse(content: content)
    }

    func credential(for url: URL) -> RegistryCredential? {
        guard let host = url.host?.lowercased() else { return nil }
        let machine = machines.last(where: { $0.name == host }) ?? machines.first(where: \.isDefault)
        return machine.map { RegistryCredential(user: $0.login, password: $0.password) }
    }

    private static func parse(content: String) -> [Machine] {
        var tokens = tokenize(content)
        var machines: [Machine] = []
        while let token = tokens.first {
            switch token {
            case "machine":
                tokens.removeFirst()
                guard let name = tokens.popFirst() else { continue }
                if let machine = parseMachine(name: name.lowercased(), tokens: &tokens) {
                    machines.append(machine)
                }
            case "default":
                tokens.removeFirst()
                if let machine = parseMachine(name: "default", tokens: &tokens) {
                    machines.append(machine)
                }
            default:
                tokens.removeFirst()
            }
        }
        return machines
    }

    private static func parseMachine(name: String, tokens: inout [String]) -> Machine? {
        var login: String?
        var password: String?
        while let key = tokens.first {
            if key == "machine" || key == "default" { break }
            tokens.removeFirst()
            switch key {
            case "login":
                login = tokens.popFirst()
            case "password":
                password = tokens.popFirst()
            default:
                _ = tokens.popFirst()
            }
            if login != nil, password != nil {
                while let key = tokens.first, key != "machine", key != "default" {
                    tokens.removeFirst()
                }
                break
            }
        }
        guard let login, let password else { return nil }
        return Machine(name: name, login: login, password: password)
    }

    private static func tokenize(_ content: String) -> [String] {
        var tokens: [String] = []
        var token = ""
        var inQuote = false
        var skippingComment = false

        for character in content {
            if skippingComment {
                if character == "\n" {
                    skippingComment = false
                }
                continue
            }
            if !inQuote, character == "#" {
                if !token.isEmpty {
                    tokens.append(token)
                    token = ""
                }
                skippingComment = true
                continue
            }
            if character == "\"" {
                inQuote.toggle()
                continue
            }
            if !inQuote, character.isWhitespace {
                if !token.isEmpty {
                    tokens.append(token)
                    token = ""
                }
                continue
            }
            token.append(character)
        }
        if !token.isEmpty {
            tokens.append(token)
        }
        return tokens
    }

    private struct Machine {
        let name: String
        let login: String
        let password: String

        var isDefault: Bool { name == "default" }
    }
}

private enum RegistryKeychain {
    static func credential(for url: URL) async -> RegistryCredential? {
        #if canImport(Security)
            guard let searchQuery = query(for: url, includeData: false) else { return nil }
            var items: CFTypeRef?
            let status = SecItemCopyMatching(searchQuery as CFDictionary, &items)
            guard status == errSecSuccess, let existingItems = items as? [[String: Any]] else {
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
                case (.some(let left), .some(let right)):
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
            guard SecItemCopyMatching(detailQuery as CFDictionary, &detail) == errSecSuccess,
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

    #if canImport(Security)
        private static func query(for url: URL, includeData: Bool) -> [String: Any]? {
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
            "/usr/bin/unzip", ["-q", archivePath.path, "-d", destination.path])
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
            headers: await headers(
                accept: "application/vnd.swift.registry.v1+json",
                registryURL: registryURL,
                registryConfig: registryConfig
            ))
        let info = try JSONDecoder().decode(ReleaseInfo.self, from: data)
        guard
            let resource = info.resources.first(where: {
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
            headers: await headers(
                accept: "application/vnd.swift.registry.v1+zip",
                registryURL: registryURL,
                registryConfig: registryConfig
            ))
    }

    private static func headers(
        accept: String,
        registryURL: URL,
        registryConfig: RegistryConfig
    ) async -> [String: String] {
        var headers = ["Accept": accept]
        if let authorization = await RegistryAuthorization.header(
            for: registryURL, registryConfig: registryConfig)
        {
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

private extension Array where Element == String {
    mutating func popFirst() -> String? {
        isEmpty ? nil : removeFirst()
    }
}

extension URL {
    fileprivate var isLocalhost: Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}
