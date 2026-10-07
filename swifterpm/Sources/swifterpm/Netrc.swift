import Foundation

/// Where netrc credentials are read from when authenticating registry and HTTP downloads.
public struct SwifterPMNetrcConfiguration: Equatable, Sendable {
    /// When false, HTTP downloads skip file netrc. Inline data and registry netrc
    /// remain enabled, matching SwiftPM's separate authorization providers.
    public var isEnabled: Bool
    /// An explicit netrc file, as passed through `--netrc-file`. When nil the
    /// `SWIFTPM_NETRC_DATA` environment variable and `~/.netrc` are used.
    public var path: URL?
    /// `--netrc`, SwiftPM's `forceNetrc`: skip the OS credential store for registry
    /// requests so a netrc entry beats a keychain item for the same host.
    public var forcesNetrc: Bool
    /// `--disable-keychain`, SwiftPM's `SecurityOptions.keychain = false`: skip the OS
    /// credential store for source-control and binary artifact downloads. It does not
    /// affect registry auth, matching `SwiftCommandState.getRegistryAuthorizationProvider`
    /// which gates the registry keychain provider on `forceNetrc` alone. The flag is
    /// forwarded to a child `swift package` subprocess so its own provider agrees.
    public var disableKeychain: Bool

    public init(
        isEnabled: Bool = true,
        path: URL? = nil,
        forcesNetrc: Bool = false,
        disableKeychain: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.path = path
        self.forcesNetrc = forcesNetrc
        self.disableKeychain = disableKeychain
    }

    public static let `default` = SwifterPMNetrcConfiguration()
}

/// Where parsed netrc entries came from. SwiftPM selects registry providers and
/// resolves duplicate machines differently for inline data and files.
enum NetrcOrigin: Equatable, Sendable {
    /// `SWIFTPM_NETRC_DATA`.
    case environment
    /// `--netrc-file`, or `~/.netrc` when no file was given.
    case file
}

struct NetrcSource: Sendable {
    let origin: NetrcOrigin
    let machines: [NetrcMachine]
}

/// The netrc credentials a resolution runs with, read and parsed once up front so
/// every later lookup is a search over `sources` rather than another file read.
struct Netrc: Sendable {
    static let empty = Netrc(configuration: .default, sources: [])

    /// What was asked for, kept so a child `swift package` invocation can be given
    /// the same flags this process resolved from.
    let configuration: SwifterPMNetrcConfiguration
    /// Parsed sources in priority order, the environment ahead of any file, matching
    /// the order SwiftPM appends its netrc providers in.
    private let sources: [NetrcSource]

    init(configuration: SwifterPMNetrcConfiguration = .default, sources: [NetrcSource]) {
        self.configuration = configuration
        self.sources = sources
    }

    /// Skips the keychain for registry requests, SwiftPM's `forceNetrc`.
    var forcesNetrc: Bool { configuration.forcesNetrc }

    var hasEnvironmentSource: Bool { sources.contains { $0.origin == .environment } }

    /// Skips the OS credential store entirely, SwiftPM's `--disable-keychain`.
    var keychainDisabled: Bool { configuration.disableKeychain }

    /// The netrc flags to hand a child `swift package` invocation so it authenticates
    /// against the same credentials this process does.
    var swiftPackageArguments: [String] {
        var arguments: [String] = []
        if configuration.isEnabled {
            if let path = configuration.path {
                arguments.append(contentsOf: ["--netrc-file", path.path])
            }
        } else {
            arguments.append("--disable-netrc")
        }
        if configuration.forcesNetrc {
            arguments.append("--netrc")
        }
        if configuration.disableKeychain {
            arguments.append("--disable-keychain")
        }
        return arguments
    }

    static func resolve(
        _ configuration: SwifterPMNetrcConfiguration,
        environment: [String: String]
    ) async throws -> Netrc {
        // SwiftPM rejects this pair outright rather than letting one win, and this is
        // the choke point every entry point goes through, embedders included.
        if !configuration.isEnabled, configuration.path != nil {
            throw ToolError.message("'--disable-netrc' and '--netrc-file' are mutually exclusive")
        }
        var sources: [NetrcSource] = []
        if let data = environment["SWIFTPM_NETRC_DATA"], !data.isEmpty,
           let machines = try? validatedMachines(in: data)
        {
            sources.append(NetrcSource(origin: .environment, machines: machines))
        }

        // An explicit `--netrc-file` replaces `~/.netrc`, and it has to be there.
        // SwiftPM refuses to run on a missing one rather than downgrading to
        // unauthenticated requests, which would surface much later as an opaque 401
        // or 404 from a private registry.
        if let path = configuration.path {
            guard try await fileSystem.exists(path.absolutePath, isDirectory: false) else {
                throw ToolError.message("did not find netrc file at \(path.path)")
            }
            sources.append(
                NetrcSource(origin: .file, machines: try validatedMachines(in: await contents(of: path), allowEmpty: true)))
        } else if let home = environment["HOME"] {
            let path = URL(fileURLWithPath: home).appendingPathComponent(".netrc")
            if let content = try? await contents(of: path),
               let machines = try? validatedMachines(in: content)
            {
                sources.append(NetrcSource(origin: .file, machines: machines))
            }
        }
        return Netrc(configuration: configuration, sources: sources)
    }

    func credential(for url: URL) -> RegistryCredential? {
        credential(for: url, in: sources.filter {
            $0.origin == .environment || configuration.isEnabled
        })
    }

    func credential(for url: URL, from origin: NetrcOrigin) -> RegistryCredential? {
        credential(for: url, in: sources.filter { $0.origin == origin })
    }

    private func credential(for url: URL, in sources: [NetrcSource]) -> RegistryCredential? {
        guard let host = url.host?.lowercased() else { return nil }
        for source in sources {
            // SwiftPM uses distinct providers: inline data selects the first match,
            // while NetrcAuthorizationProvider selects the last match in a file.
            let match = source.origin == .environment
                ? source.machines.first(where: { $0.name == host })
                : source.machines.last(where: { $0.name == host })
            if let machine = match ?? source.machines.first(where: \.isDefault)
            {
                return RegistryCredential(user: machine.login, password: machine.password)
            }
        }
        return nil
    }

    private static func validatedMachines(in content: String, allowEmpty: Bool = false) throws -> [NetrcMachine] {
        let machines = NetrcParser.machines(in: content)
        guard allowEmpty || !machines.isEmpty else {
            throw ToolError.message("netrc contains no machines")
        }
        if let index = machines.firstIndex(where: \.isDefault), index != machines.count - 1 {
            throw ToolError.message("netrc default entry must be last")
        }
        return machines
    }

    private static func contents(of path: URL) async throws -> String {
        let data = try await fileSystem.readFile(at: path.absolutePath)
        guard let content = String(data: data, encoding: .utf8) else {
            throw ToolError.message("netrc file at \(path.path) is not valid UTF-8")
        }
        return content
    }
}

struct NetrcMachine: Equatable, Sendable {
    let name: String
    let login: String
    let password: String

    var isDefault: Bool { name == "default" }
}

enum NetrcParser {
    /// netrc is a token stream rather than a line-oriented format, so the content is
    /// flattened into tokens first and then scanned for the two keywords that open an
    /// entry. Anything else at that level is skipped, which is what lets `macdef`
    /// blocks and unknown fields pass through without derailing the scan.
    static func machines(in content: String) -> [NetrcMachine] {
        var tokens = tokenize(content)
        var machines: [NetrcMachine] = []
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

    private static func parseMachine(name: String, tokens: inout [String]) -> NetrcMachine? {
        var login: String?
        var password: String?
        while let key = tokens.first {
            if key == "machine" || key == "default" { break }
            tokens.removeFirst()
            switch key {
            case "login":
                login = tokens.popFirstValue()
            case "password":
                password = tokens.popFirstValue()
            default:
                _ = tokens.popFirstValue()
            }
            if login != nil, password != nil {
                while let key = tokens.first, key != "machine", key != "default" {
                    tokens.removeFirst()
                }
                break
            }
        }
        guard let login, let password else { return nil }
        return NetrcMachine(name: name, login: login, password: password)
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
            // Only a `#` that opens a token starts a comment. SwiftPM's netrc regex
            // requires whitespace ahead of it and curl agrees, so `password se#cret`
            // is a password rather than a truncated one followed by a comment.
            if !inQuote, character == "#", token.isEmpty {
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
}

private extension Array where Element == String {
    mutating func popFirst() -> String? {
        isEmpty ? nil : removeFirst()
    }

    /// Pops a value, refusing one that opens the next entry. A `login` or `password`
    /// whose value never materialises, from an empty quoted string or a value that
    /// starts a comment, would otherwise consume the following `machine` keyword and
    /// take the rest of the file down with it.
    mutating func popFirstValue() -> String? {
        guard let first, first != "machine", first != "default" else { return nil }
        return removeFirst()
    }
}
