import Foundation

/// Where netrc credentials are read from when authenticating registry and HTTP downloads.
public struct SwifterPMNetrcConfiguration: Equatable, Sendable {
    /// When false, no netrc source is consulted at all.
    public var isEnabled: Bool
    /// An explicit netrc file, as passed through `--netrc-file`. When nil the
    /// `SWIFTPM_NETRC_DATA` environment variable and `~/.netrc` are used.
    public var path: URL?

    public init(isEnabled: Bool = true, path: URL? = nil) {
        self.isEnabled = isEnabled
        self.path = path
    }

    public static let `default` = SwifterPMNetrcConfiguration()
}

enum Netrc {
    /// SwiftPM refuses to run when `--netrc-file` points at a file that isn't there rather than
    /// downgrading to unauthenticated requests, which would otherwise surface much later as an
    /// opaque 401 or 404 from a private registry.
    static func validate(_ configuration: SwifterPMNetrcConfiguration) async throws {
        guard configuration.isEnabled, let path = configuration.path else { return }
        guard try await fileSystem.exists(path.absolutePath, isDirectory: false) else {
            throw ToolError.message("did not find netrc file at \(path.path)")
        }
    }

    static func credential(
        for url: URL,
        environment: [String: String]
    ) async -> RegistryCredential? {
        let configuration = Environment.netrcConfiguration
        guard configuration.isEnabled else { return nil }

        if let path = configuration.path {
            return await credential(for: url, atPath: path)
        }

        if let data = environment["SWIFTPM_NETRC_DATA"], !data.isEmpty,
           let credential = RegistryNetrc(content: data).credential(for: url)
        {
            return credential
        }

        guard let home = environment["HOME"] else { return nil }
        return await credential(
            for: url,
            atPath: URL(fileURLWithPath: home).appendingPathComponent(".netrc")
        )
    }

    private static func credential(for url: URL, atPath path: URL) async -> RegistryCredential? {
        guard let data = try? await fileSystem.readFile(at: path.absolutePath),
              let content = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return RegistryNetrc(content: content).credential(for: url)
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

private extension Array where Element == String {
    mutating func popFirst() -> String? {
        isEmpty ? nil : removeFirst()
    }
}
