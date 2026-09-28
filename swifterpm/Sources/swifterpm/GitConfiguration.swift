import Foundation

/// The parts of git's configuration that decide whether a plain `git` invocation can find a
/// credential for a location on its own.
///
/// Read once per process rather than per package: every dependency gets the same answer,
/// and each read is a subprocess. Only the system, global and XDG scopes are read, because
/// swifterpm fetches into freshly `git init`-ed scratch directories — the local config that
/// applies to a dependency fetch is empty, so reading the user's project config would apply
/// rules git itself would not.
struct GitConfiguration: Sendable {
    static let empty = GitConfiguration(insteadOfPrefixes: [], hasUnscopedHelper: false, helperURLs: [])

    /// The right-hand side of every `url.<base>.insteadOf`, which is what git matches a
    /// location against.
    private let insteadOfPrefixes: [String]
    /// A `credential.helper` with no URL subsection, which answers for every host.
    private let hasUnscopedHelper: Bool
    /// The URL subsection of every `credential.<url>.helper`.
    private let helperURLs: [String]

    init(insteadOfPrefixes: [String], hasUnscopedHelper: Bool, helperURLs: [String]) {
        self.insteadOfPrefixes = insteadOfPrefixes
        self.hasUnscopedHelper = hasUnscopedHelper
        self.helperURLs = helperURLs
    }

    /// Whether git would find a credential for `location` without swifterpm injecting one.
    ///
    /// Answered fail-safe. `credential.<url>` has matching rules of its own — exact protocol,
    /// exact host or a leading `*.` wildcard, path only under `credential.useHttpPath` — and
    /// getting them subtly wrong in the "no match" direction reintroduces the bug this
    /// ordering exists to fix. So the path is never used to rule a helper out, and anything
    /// unrecognised counts as a match.
    func canAuthenticate(_ location: String) -> Bool {
        if hasUnscopedHelper { return true }
        // `insteadOf` is a literal longest-prefix string match, with no URL parsing at all.
        if insteadOfPrefixes.contains(where: { !$0.isEmpty && location.hasPrefix($0) }) { return true }
        guard let url = URL(string: location), let host = url.host?.lowercased() else {
            return !helperURLs.isEmpty
        }
        return helperURLs.contains { helperURL in
            guard let configured = URL(string: helperURL),
                  let configuredHost = configured.host?.lowercased()
            else {
                return true
            }
            if let scheme = configured.scheme, scheme.lowercased() != (url.scheme ?? "").lowercased() {
                return false
            }
            if configuredHost.hasPrefix("*.") {
                return host.hasSuffix(String(configuredHost.dropFirst(1)))
            }
            return configuredHost == host
        }
    }

    static func parse(_ output: String) -> GitConfiguration {
        var insteadOfPrefixes: [String] = []
        var hasUnscopedHelper = false
        var helperURLs: [String] = []

        for record in output.split(separator: "\0", omittingEmptySubsequences: true) {
            let newline = record.firstIndex(of: "\n")
            let key = String(newline.map { record[..<$0] } ?? record)
            let value = newline.map { String(record[record.index(after: $0)...]) } ?? ""
            let lowercasedKey = key.lowercased()

            if lowercasedKey.hasPrefix("url."), lowercasedKey.hasSuffix(".insteadof") {
                if !value.isEmpty { insteadOfPrefixes.append(value) }
                continue
            }
            guard lowercasedKey.hasPrefix("credential."), lowercasedKey.hasSuffix(".helper") else {
                continue
            }
            // An empty value resets the helper list rather than configuring one.
            guard !value.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            if lowercasedKey == "credential.helper" {
                hasUnscopedHelper = true
            } else {
                let subsection = key.dropFirst("credential.".count).dropLast(".helper".count)
                helperURLs.append(String(subsection))
            }
        }

        return GitConfiguration(
            insteadOfPrefixes: insteadOfPrefixes,
            hasUnscopedHelper: hasUnscopedHelper,
            helperURLs: helperURLs
        )
    }
}

/// Loads the configuration once and hands the same answer to every later caller.
private actor GitConfigurationCache {
    private var cached: GitConfiguration?

    func load() async -> GitConfiguration {
        if let cached { return cached }
        let configuration = await Self.read()
        cached = configuration
        return configuration
    }

    private static func read() async -> GitConfiguration {
        // Run outside any working copy so only the system, global and XDG scopes are read.
        // `git config --system` is not equivalent: on macOS the toolchain's unscoped
        // `credential.helper = osxkeychain` lives in a gitconfig that scope does not cover.
        let output = try? await SystemProcess.output(
            "/usr/bin/git",
            ["config", "-z", "--get-regexp", #"^(url|credential)\."#],
            workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
        )
        return output.map(GitConfiguration.parse) ?? .empty
    }
}

private let gitConfigurationCache = GitConfigurationCache()

/// Answers whether git can authenticate a location by itself, which is what decides where
/// the credential-free attempt goes in the ladder.
enum GitCredentialDiscovery {
    static func gitCanAuthenticate(_ location: String) async -> Bool {
        guard let url = URL(string: location) else { return true }

        // `GIT_ASKPASS` authenticates without netrc, a rewrite or a helper, and being an
        // environment variable it is invisible to the config parse.
        let environment = Environment.current
        if environment["GIT_ASKPASS"] != nil || environment["SSH_ASKPASS"] != nil { return true }

        // Only the netrc git reads for itself counts. A `--netrc-file` or `SWIFTPM_NETRC_DATA`
        // source is unreachable from curl, so it is a reason to inject rather than to defer.
        if Environment.netrc.gitVisibleCredential(for: url) != nil { return true }

        if let configuration = Environment.gitConfiguration {
            return configuration.canAuthenticate(location)
        }
        return await gitConfigurationCache.load().canAuthenticate(location)
    }
}
