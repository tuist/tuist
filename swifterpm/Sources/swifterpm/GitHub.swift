import Foundation

struct GitHubRepo {
    let owner: String
    let repo: String

    init(location: String) throws {
        let normalized =
            location.hasPrefix("git@github.com:")
                ? location.replacingOccurrences(of: "git@github.com:", with: "https://github.com/")
                : location
        guard let url = URL(string: normalized), url.host == "github.com" else {
            throw ToolError.message("not a GitHub URL")
        }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else {
            throw ToolError.message("GitHub URL has no owner or repo")
        }
        owner = parts[0]
        repo = parts[1].hasSuffix(".git") ? String(parts[1].dropLast(4)) : parts[1]
    }
}

/// Caches only the `gh auth token` subprocess. Reading the environment is free and has to
/// observe `Environment.current` rather than a value memoized on first use, so it stays out.
private actor GitHubCLITokenCache {
    private var loaded = false
    private var cachedToken: String?

    func token() async -> String? {
        if loaded {
            return cachedToken
        }
        loaded = true

        guard let output = try? await SystemProcess.output("/usr/bin/env", ["gh", "auth", "token"])
        else {
            return nil
        }
        let token = output.trimmingCharacters(in: .whitespacesAndNewlines)
        cachedToken = token.isEmpty ? nil : token
        return cachedToken
    }
}

private let githubCLITokenCache = GitHubCLITokenCache()

enum GitHubAuth {
    static func token() async -> String? {
        let environment = Environment.current
        if let token = environment["GITHUB_TOKEN"] ?? environment["GH_TOKEN"],
           !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return token
        }
        return await githubCLITokenCache.token()
    }

    static func hasSession() async -> Bool {
        await token() != nil
    }
}

enum SourceControlLocations {
    static func canonicalResolvedFileLocation(_ location: String) -> String {
        if let shorthandLocation = ColonSeparatedGitLocation(location) {
            return shorthandLocation.canonicalString
        }
        guard var components = URLComponents(string: location),
              let host = components.host
        else {
            return location
        }

        components.scheme = components.scheme?.lowercased()
        let normalizedHost = host.lowercased()
        components.host = normalizedHost
        if canonicalizesProviderPath(host: normalizedHost) {
            components.path = canonicalProviderPath(components.path)
        }
        return components.string ?? location
    }

    static func fetchCandidates(_ location: String) -> [String] {
        var locations = [location]
        appendGitHubLocations(for: location, to: &locations)
        appendGitLabLocations(for: location, to: &locations)
        return locations
    }

    /// Every candidate location crossed with the credentials to try it with, flattened
    /// into the order the fetch loops walk.
    static func fetchAttempts(_ location: String) async -> [GitFetchAttempt] {
        var attempts: [GitFetchAttempt] = []
        for candidate in fetchCandidates(location) {
            attempts.append(contentsOf: await GitTransportAuth.attempts(for: candidate))
        }
        return attempts
    }

    /// Identifies the package a location points at, collapsing the HTTPS and SSH forms
    /// `fetchCandidates` produces onto one key so a credential resolved through one form
    /// is reused for the other.
    static func packageIdentity(_ location: String) -> String {
        if let repo = try? GitHubRepo(location: location) {
            return "github.com/\(repo.owner.lowercased())/\(repo.repo.lowercased())"
        }
        if let repo = try? GitLabRepo(location: location) {
            return "\(repo.host)/\(repo.pathWithNamespace.lowercased())"
        }
        return canonicalResolvedFileLocation(location)
    }

    /// Offer both the HTTPS and SSH forms regardless of how the location was originally
    /// declared. The original is tried first, so SSH-declared dependencies keep using
    /// ssh-agent locally while still falling back to HTTPS in environments (typically CI)
    /// that only have a token-based `git config insteadOf` rewrite or anonymous HTTPS access.
    private static func appendGitHubLocations(for location: String, to locations: inout [String]) {
        guard let repo = try? GitHubRepo(location: location) else { return }
        appendUnique("https://github.com/\(repo.owner)/\(repo.repo).git", to: &locations)
        appendUnique("git@github.com:\(repo.owner)/\(repo.repo).git", to: &locations)
    }

    private static func appendGitLabLocations(for location: String, to locations: inout [String]) {
        guard let repo = try? GitLabRepo(location: location) else { return }
        appendUnique("https://\(repo.host)/\(repo.pathWithNamespace).git", to: &locations)
        appendUnique("git@\(repo.host):\(repo.pathWithNamespace).git", to: &locations)
    }

    private static func appendUnique(_ location: String, to locations: inout [String]) {
        if !locations.contains(location) {
            locations.append(location)
        }
    }

    fileprivate static func canonicalProviderPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let withoutGit =
            trimmed.lowercased().hasSuffix(".git")
                ? String(trimmed.dropLast(4)) : trimmed
        return withoutGit.isEmpty ? "" : "/\(withoutGit)"
    }

    fileprivate static func canonicalizesProviderPath(host: String) -> Bool {
        let host = host.lowercased()
        return host == "github.com" || GitLabRepo.isKnownHost(host)
    }
}

/// How one fetch attempt authenticates. A candidate location is tried with each of these
/// in turn, most specific first, so an ambient provider token is only ever a last resort.
enum GitTransportCredential: Equatable, Sendable, CustomStringConvertible {
    /// Whatever git resolves on its own: ~/.netrc, a credential helper, a
    /// `url.<...>.insteadOf` rewrite, or ssh-agent on an SSH candidate.
    case gitConfigured
    /// A netrc entry git cannot reach by itself, from `--netrc-file` or `SWIFTPM_NETRC_DATA`.
    case netrc
    /// `GITHUB_TOKEN`, `GH_TOKEN`, or `gh auth token`.
    case gitHubToken
    /// `GITLAB_TOKEN`, `CI_JOB_TOKEN`, and the other GitLab environment tokens.
    case gitLabToken

    var description: String {
        switch self {
        case .gitConfigured: return "git's configured credentials"
        case .netrc: return "netrc"
        case .gitHubToken: return "an ambient GitHub token"
        case .gitLabToken: return "an ambient GitLab token"
        }
    }
}

/// One candidate location paired with the credential to try it with.
struct GitFetchAttempt: Sendable {
    let location: String
    let credential: GitTransportCredential
    let configArguments: [String]
}

/// Remembers which credential authenticated a package, so the requests that follow the
/// first one reuse the answer instead of walking the ladder again.
///
/// Keyed by package rather than by host, because access differs per repository — an
/// enterprise-managed token reads one org's repositories and a `~/.netrc` account reads
/// another's, both on `github.com`, and a host-keyed answer would poison one with the other.
actor ResolvedPackageCredentials {
    static let shared = ResolvedPackageCredentials()

    private var credentials: [String: GitTransportCredential] = [:]

    func record(_ credential: GitTransportCredential, for location: String) {
        credentials[SourceControlLocations.packageIdentity(location)] = credential
    }

    func credential(for location: String) -> GitTransportCredential? {
        credentials[SourceControlLocations.packageIdentity(location)]
    }
}

/// Orders the credentials a candidate location is tried with.
///
/// The HTTPS candidate `fetchCandidates` adds is useless in CI without a credential, so
/// swifterpm injects the provider token it already discovers for the API as an
/// `http.<base>.extraheader`, the way `actions/checkout` does, which keeps it out of the
/// on-disk git config.
///
/// That header used to go on unconditionally, which made it an override rather than a
/// fallback. `http.<base>.extraheader` beats every credential git would have found for
/// itself, and against GitHub it also stops curl consulting ~/.netrc, so the request 401s
/// and git falls through to a prompt that `nonInteractiveGitEnvironment` has disabled. A
/// token that cannot read the repository — a `gh` login on a personal account, one not
/// authorized for a SAML-SSO org, a `GITHUB_TOKEN` exported for unrelated tooling — turned
/// a working checkout into the same failure as having no credential at all, on machines
/// where plain git and SwiftPM both succeed.
///
/// So the token stops being an override and becomes a rung. Git resolves the credential
/// itself, exactly as it did before swifterpm, alongside a netrc source only swifterpm can
/// see and the ambient token, and whichever the ladder reaches first that works is used.
///
/// Which rung goes first is decided by reading git's own configuration once, because both
/// orderings waste a request in the setup they do not suit. When a rewrite rule, a
/// credential helper or `~/.netrc` covers the host, git can authenticate unaided and goes
/// first. When nothing does — a CI runner holding only a token — the injected credential
/// goes first instead, and the credential-free attempt trails it rather than being dropped:
/// a public dependency needs no credential at all, so a broken or expired token must never
/// be the only thing tried.
enum GitTransportAuth {
    static func attempts(for location: String) async -> [GitFetchAttempt] {
        let bare = GitFetchAttempt(
            location: location, credential: .gitConfigured, configArguments: []
        )
        // SSH candidates are always tried bare: ssh-agent is invisible to git's config and
        // there is no token form for SSH anyway.
        guard location.hasPrefix("https://"),
              let url = URL(string: location),
              let host = url.host
        else {
            return [bare]
        }

        var injected: [GitFetchAttempt] = []

        // `~/.netrc` is already covered by the bare attempt, since git reads it through
        // curl. This one carries the sources git has no way to know about.
        if let credential = Environment.netrc.credential(for: url) {
            let encoded = basicCredential(user: credential.user, token: credential.password)
            injected.append(
                GitFetchAttempt(
                    location: location,
                    credential: .netrc,
                    configArguments: extraHeaderArguments(
                        base: "https://\(host)/", authorization: "Basic \(encoded)"
                    )
                )
            )
        }

        if (try? GitHubRepo(location: location)) != nil, let token = await GitHubAuth.token() {
            injected.append(
                GitFetchAttempt(
                    location: location,
                    credential: .gitHubToken,
                    configArguments: gitHubArguments(token: token)
                )
            )
        } else if let repo = try? GitLabRepo(location: location),
                  let token = await GitLabAuth.token(host: repo.host)
        {
            injected.append(
                GitFetchAttempt(
                    location: location,
                    credential: .gitLabToken,
                    configArguments: gitLabArguments(host: repo.host, token: token)
                )
            )
        }

        guard !injected.isEmpty else { return [bare] }
        if await GitCredentialDiscovery.gitCanAuthenticate(location) {
            return [bare] + injected
        }
        return injected + [bare]
    }

    static func gitHubArguments(token: String) -> [String] {
        extraHeaderArguments(
            base: "https://github.com/",
            authorization: "Basic \(basicCredential(user: "x-access-token", token: token))"
        )
    }

    static func gitLabArguments(host: String, token: GitLabAuth.Token) -> [String] {
        extraHeaderArguments(base: "https://\(host)/", authorization: token.gitHTTPAuthorization)
    }

    private static func extraHeaderArguments(base: String, authorization: String) -> [String] {
        ["-c", "http.\(base).extraheader=Authorization: \(authorization)"]
    }

    private static func basicCredential(user: String, token: String) -> String {
        Data("\(user):\(token)".utf8).base64EncodedString()
    }
}

private struct ColonSeparatedGitLocation {
    let user: String
    let host: String
    let path: String

    init?(_ location: String) {
        guard !location.contains("://"),
              let at = location.firstIndex(of: "@"),
              let colon = location[location.index(after: at)...].firstIndex(of: ":")
        else {
            return nil
        }

        let user = String(location[..<at])
        let host = String(location[location.index(after: at) ..< colon])
        let path = String(location[location.index(after: colon)...])
        guard !user.isEmpty, !host.isEmpty, !path.isEmpty else { return nil }

        self.user = user
        self.host = host
        self.path = path
    }

    var canonicalString: String {
        let normalizedHost = host.lowercased()
        let normalizedPath = if SourceControlLocations.canonicalizesProviderPath(host: normalizedHost) {
            SourceControlLocations.canonicalProviderPath(path)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else {
            path
        }
        return "\(user)@\(normalizedHost):\(normalizedPath)"
    }
}
