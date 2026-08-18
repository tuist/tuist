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

private actor GitHubTokenCache {
    /// Memoises the in-flight resolution rather than a `loaded` flag: resolving awaits
    /// `gh` and a network probe, and restores run up to 32 tasks at once, so a flag set
    /// before the first suspension hands every concurrent caller a nil token while the
    /// first one is still resolving.
    private var resolution: Task<String?, Never>?

    func token() async -> String? {
        if let resolution {
            return await resolution.value
        }
        let task = Task { await Self.resolveToken() }
        resolution = task
        return await task.value
    }

    private static func resolveToken() async -> String? {
        guard let token = await discoveredToken() else { return nil }
        return await GitHubTokenProbe.acceptsGitHubDotCom(token: token) ? token : nil
    }

    private static func discoveredToken() async -> String? {
        let env = ProcessInfo.processInfo.environment
        if let token = env["GITHUB_TOKEN"] ?? env["GH_TOKEN"],
           !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return token
        }

        guard let output = try? await SystemProcess.output("/usr/bin/env", ["gh", "auth", "token"])
        else {
            return nil
        }
        let token = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }
}

/// A token discovered from the environment or from `gh` is not necessarily a github.com
/// token. An enterprise CI exports its GitHub Enterprise `GITHUB_TOKEN` under the same
/// name, and github.com answers it with 401. Sending it anyway is worse than sending
/// nothing: it fails the archive download, and the `extraheader` it puts on the HTTPS git
/// fallback makes even a public repository unfetchable, so a dependency graph that
/// anonymous access would have restored fails outright. Probing once tells the two cases
/// apart. `/rate_limit` is the endpoint to probe with because it does not spend from the
/// budget it reports.
enum GitHubTokenProbe {
    static let url = URL(string: "https://api.github.com/rate_limit")!

    static func acceptsGitHubDotCom(token: String) async -> Bool {
        do {
            _ = try await HTTPClient.data(
                url: url,
                headers: ["User-Agent": "swifterpm/0.1", "Authorization": "Bearer \(token)"]
            )
            return acceptsToken(probeStatus: 200)
        } catch let error as HTTPStatusError {
            return acceptsToken(probeStatus: error.statusCode)
        } catch {
            return acceptsToken(probeStatus: nil)
        }
    }

    /// Only an explicit 401 disqualifies a token. A transport failure (nil) or any other
    /// status keeps it, so an offline run, a proxy, or a 403 from an org IP allowlist
    /// never silently downgrades a working credential to anonymous access.
    static func acceptsToken(probeStatus: Int?) -> Bool {
        guard let probeStatus else { return true }
        return probeStatus != 401
    }
}

/// Where to download a commit's source archive from.
///
/// The REST tarball endpoint spends from the API budget, which is 5,000 requests an hour
/// with a token but 60 without one, so an anonymous restore of a dependency graph of any
/// size exhausts it and falls back to git for the remainder. codeload is where that
/// endpoint redirects and it serves public repositories without touching the budget, so
/// anonymous restores address it directly. Authenticated restores keep using the REST
/// endpoint, which is also what reaches private repositories.
enum GitHubArchiveURL {
    static func make(repo: GitHubRepo, revision: String, authenticated: Bool) -> URL {
        if authenticated {
            return URL(
                string: "https://api.github.com/repos/\(repo.owner)/\(repo.repo)/tarball/\(revision)"
            )!
        }
        return URL(
            string: "https://codeload.github.com/\(repo.owner)/\(repo.repo)/tar.gz/\(revision)"
        )!
    }
}

private let githubTokenCache = GitHubTokenCache()

enum GitHubAuth {
    static func token() async -> String? {
        await githubTokenCache.token()
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

/// Authenticates the HTTPS git fallback with the same token swifterpm discovers for the
/// provider's API. Without this, the HTTPS candidate added by `fetchCandidates` only works
/// when an ambient credential (a `url.insteadOf` token rewrite, a credential helper, or
/// ~/.netrc) is configured, so an SSH-declared private dependency keeps failing in CI even
/// with a usable `GITHUB_TOKEN`/`GH_TOKEN`. Emitting an `http.<base>.extraheader` via `-c`
/// mirrors what `actions/checkout` does and keeps the token out of the on-disk git config.
/// SSH candidates return no arguments so ssh-agent stays in charge, and when no token is
/// available we add nothing so configured ambient credentials keep working unchanged.
enum GitTransportAuth {
    static func configArguments(for location: String) async -> [String] {
        guard location.hasPrefix("https://") else { return [] }
        if (try? GitHubRepo(location: location)) != nil {
            guard let token = await GitHubAuth.token() else { return [] }
            return gitHubArguments(token: token)
        }
        if let repo = try? GitLabRepo(location: location) {
            guard let token = await GitLabAuth.token(host: repo.host) else { return [] }
            return gitLabArguments(host: repo.host, token: token)
        }
        return []
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
