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
    private var loaded = false
    private var cachedToken: String?

    func token() async -> String? {
        if loaded {
            return cachedToken
        }
        loaded = true

        if let token = GitHubAuth.envToken(from: ProcessInfo.processInfo.environment) {
            cachedToken = token
            return token
        }

        guard let output = try? await SystemProcess.output(
            "/usr/bin/env", ["gh", "auth", "token", "--hostname", "github.com"]
        )
        else {
            return nil
        }
        let token = output.trimmingCharacters(in: .whitespacesAndNewlines)
        cachedToken = token.isEmpty ? nil : token
        return cachedToken
    }
}

private let githubTokenCache = GitHubTokenCache()

enum GitHubAuth {
    private static let dedicatedEnvKey = "SWIFTERPM_GITHUB_TOKEN"
    private static let ambientEnvKeys = ["GITHUB_TOKEN", "GH_TOKEN"]

    /// `GitHubAuth` only ever authenticates github.com: `GitHubRepo` rejects every other host
    /// and the API calls go to api.github.com. `GITHUB_TOKEN` and `GH_TOKEN` are ambient, and
    /// GitHub Actions on a GitHub Enterprise Server instance exports them holding a credential
    /// for that instance, which github.com answers with a 401. `GITHUB_SERVER_URL`,
    /// `GITHUB_API_URL` and `GH_HOST` name the instance those credentials belong to, so they
    /// are only used when all of them point at github.com. Naming `SWIFTERPM_GITHUB_TOKEN` is
    /// itself a statement that the token is meant for github.com, so it is taken as given.
    static func envToken(from environment: [String: String]) -> String? {
        if let token = nonEmpty(environment[dedicatedEnvKey]) {
            return token
        }
        guard belongsToGitHubDotCom(environment) else { return nil }
        for key in ambientEnvKeys {
            if let token = nonEmpty(environment[key]) { return token }
        }
        return nil
    }

    static func token() async -> String? {
        await githubTokenCache.token()
    }

    static func hasSession() async -> Bool {
        await token() != nil
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func belongsToGitHubDotCom(_ environment: [String: String]) -> Bool {
        ["GITHUB_SERVER_URL", "GITHUB_API_URL", "GH_HOST"]
            .compactMap { environment[$0] }
            .compactMap(host(of:))
            .allSatisfy { $0 == "github.com" || $0 == "api.github.com" }
    }

    private static func host(of value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let host = URL(string: trimmed)?.host {
            return host.lowercased()
        }
        return trimmed.split(separator: "/").first.map { $0.lowercased() }
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
/// with a usable `SWIFTERPM_GITHUB_TOKEN`/`GITHUB_TOKEN`/`GH_TOKEN`. Emitting an `http.<base>.extraheader` via `-c`
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
